%%% Author: xuxb
%%% Created: 2010-4-28
%%% Description: Mobile connection server
%%% Copyright (c) 2010 www.nd.com.cn

-module(service_mobile_conn).
-behaviour(gen_server).


%%
%% Include files
%%

-include("loglevel.hrl").
-include("message_define.hrl").
-include_lib("stdlib/include/qlc.hrl").

%%
%% Exported Functions
%%

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([start_link/0, send_message/4, kickout_mobile/3, on_ctlnode_startup/1, broadcast_online/3]).

%%
%% API Functions
%%

-record(server, {control_node}).

-record(unique_ids, {type, id}).
-record(undelivered_msgs, {id = 0, mobile_id = 0, timestamp, msg_bin = <<>>, control_node}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_link() ->
	case gen_server:start_link({local, ?MODULE}, ?MODULE, [], []) of
		{ok, Pid} ->
			{ok, Pid};
		Result ->
			?CRITICAL_MSG("Start mobile push server service failed: ~p ~n", [Result]),
			Result
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% provide this method to be called by control node
%% send message to connected mobile
send_message(CtlNode, MobileId, TimeStamp, MsgBin) when is_integer(MobileId) ->
	case ets:lookup(ets_mobile_id2pid, MobileId) of
		[{MobileId, Pid, CtlNode}] ->
			send_message(CtlNode, Pid, TimeStamp, MsgBin);
		_ ->
			{error, "Can't find pid from ets_mobile_id2pid."}
	end;

send_message(CtlNode, Pid, TimeStamp, MsgBin) when is_pid(Pid) ->
	Pid ! {tcp_send, self(), CtlNode, TimeStamp, MsgBin},
	case self() of
		Pid -> ok;
		_ -> 
			receive 
				{tcp_send, ok} -> ok
			after 4999 ->
				{error, "time out"}
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% provide this method to be called by control node
%% kick out a connected mobile(maybe caused by relogin)
kickout_mobile(_MobileId, Pid, Reason) ->
	case erlang:is_process_alive(Pid) of
		true ->
			Pid ! {kick_out, Reason}, 
			ok; %% kickout mobile 
		false -> %% zombie process?
			gen_server:cast(?MODULE, {mobile_process_exit, Pid, killed}),
			exit(Pid, kill), %% kill it
			ok
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% provide this method to be called by control node
%% called when control node restart
on_ctlnode_startup(CtlNode) ->
	gen_server:cast(?MODULE, {control_node_failed, CtlNode}), %% force client to re-connect
	gen_server:cast(?MODULE, {check_local_offline_msgs, CtlNode}). %% synchronize offline messages

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% provide this mothod to be called by push node
broadcast_online(ServerId, TimeStampBin, MsgBin) ->
	TimeStamp = emobile_message:decode_timestamp(TimeStampBin),
	SleepMs   = emobile_config:get_option(broadcast_sleep),
	case ets:tab2list(ets_mobile_id2pid) of
		[] -> ok;
		L ->
			F = fun({MobileId, Pid, _}) ->
						MsgSize = 24 + byte_size(MsgBin),
						send_message(undefined, Pid, TimeStamp, <<MsgSize:2/?NET_ENDIAN-unit:8,
													   			?MSG_DELIVER:2/?NET_ENDIAN-unit:8,
													   			ServerId:4/?NET_ENDIAN-unit:8,
													   			TimeStampBin/binary, 												  
													   			1: 4/?NET_ENDIAN-unit:8,
													   			MobileId: 4/?NET_ENDIAN-unit:8,
													   			MsgBin/binary>>),
						timer:sleep(SleepMs)
				end,
			lists:foreach(F, L),
			ok
	end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init([]) ->
	process_flag(trap_exit, true), 
	
	{ok, {Ip, Port}} = check_emobile_configuration(),
	?INFO_MSG("configuration: listen_arrdr: {~p, ~p} ~n", [Ip, Port]),		
	
	
	mnesia:create_table(unique_ids, 
						[{disc_copies, [node()]},
						 {attributes, record_info(fields, unique_ids)}]),		
	
	mnesia:create_table(undelivered_msgs,
						[{disc_copies, [node()]},
						 {attributes, record_info(fields, undelivered_msgs)},
						 {index, [control_node]}]),	
	
	ets:new(ets_mobile_id2pid, [named_table]),
	ets:new(ets_pid2mobile_id, [named_table]),
		
	FHandlePacket = fun(Sock) -> 
							inet:setopts(Sock, [binary, {packet, 0}, {active, once}]),
							TimerRef = erlang:start_timer(29999, self(), login_timer),
							put(login_timer_ref, TimerRef),
							mobile_loop:loop([Sock, <<>>]) 
					end, 	
	
	FOnChildExit = fun(Pid, Why) ->
						   case ets:lookup(ets_pid2mobile_id, Pid) of
							   [{Pid, MobileId, CtlNode}] ->
								   case rpc:call(CtlNode, service_lookup_mobile_node, on_mobile_logout, [MobileId, erlang:node(), Pid]) of
									   ok -> void;
									   _ -> 
										   ?CRITICAL_MSG("RPC control node [~p] failed! ~n", [CtlNode]),
										   gen_server:cast(?MODULE, {control_node_failed, CtlNode})
								   end;
							   [] ->
								   void
						   end,
						   gen_server:cast(?MODULE, {mobile_process_exit, Pid, Why})
				   end,
	
	{ok, IpAddr} = inet:getaddr(Ip, inet), %% to confirm Ip is valid inet address
	{ok, _} = socket_server:start('MOBILE CONN TCP SERVER', IpAddr, Port, FHandlePacket, FOnChildExit),
	
	check_local_offline_msgs(),
	notify_lb_svr_startup({Ip, Port}),
	
	{ok, #server{}}.	


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
handle_cast({on_mobile_login, MobileId, Pid, CtlNode}, Server) ->
	ets:insert(ets_pid2mobile_id, {Pid, MobileId, CtlNode}),
	ets:insert(ets_mobile_id2pid, {MobileId, Pid, CtlNode}),
	rpc:cast(CtlNode, service_offline_msg, send_offline_msgs, [MobileId, node()]),
	{noreply, Server};
	
handle_cast({mobile_process_exit, Pid, _Why}, Server) ->	
	case ets:lookup(ets_pid2mobile_id, Pid) of
		[{Pid, MobileId, _CtlNode}] ->
			ets:delete(ets_pid2mobile_id, Pid),
			ets:delete(ets_mobile_id2pid, MobileId),
			{noreply, Server};
		[] ->
			{noreply, Server}
	end;	

handle_cast({control_node_failed, CtlNode}, Server) ->
	case qlc:eval(qlc:q([Pid ||  {Pid, _, MobileCtlNode} <- ets:table(ets_pid2mobile_id),
								 MobileCtlNode =:= CtlNode])) of
		[] ->
			{noreply, Server};
		PidList ->
			lists:foreach(fun(Pid) -> Pid ! {kick_out, "control node failed"} end, PidList),
			ets:match_delete(ets_pid2mobile_id, {'_', '_', CtlNode}),
			ets:match_delete(ets_mobile_id2pid, {'_', '_', CtlNode}),
			{noreply, Server}
	end;

handle_cast({check_local_offline_msgs, CtlNode}, Server) ->
	case mnesia:dirty_index_read(undelivered_msgs, CtlNode, #undelivered_msgs.control_node) of
		[] ->
			void;
		L ->
			lists:foreach(fun(#undelivered_msgs{mobile_id=MobileId, timestamp=TimeStamp, msg_bin=MsgBin}) -> 
								  mobile_network:deliver_message([MobileId], TimeStamp, MsgBin) 
						  end, L),
			lists:foreach(fun(#undelivered_msgs{id=Id}) -> mnesia:dirty_delete(undelivered_msgs, Id) end, L)
	end,
	{noreply, Server};

handle_cast(Event, Server) ->
	?INFO_MSG("receive event: ~p ~n", [Event]),
	{noreply, Server}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
handle_call(_Request, _From, Server) ->
	{reply, ok, Server}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
handle_info(Info, Server) ->
	?INFO_MSG("Mobile push server receive info: ~p ~n", [Info]),
	{noreply, Server}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
code_change(_OldVsn, Server, _Extra) ->
	{ok, Server}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
terminate(_Reason, _Server) ->
	notify_lb_svr_shutdown(),
	socket_server:stop('MOBILE CONN TCP SERVER'),
	ok.


%%
%% Local Functions
%%

%% check emobile cfg
check_emobile_configuration() ->
	ConnNodes = emobile_config:get_option(emconn_nodes),
	CtlBackNodes = emobile_config:get_option(emctl_back_nodes),	
	
	case length(CtlBackNodes) of
		0 -> 
			?CRITICAL_MSG("Start conn node[~p] failed: you should config at least ONE "
						  "control backup node, please check \"emobile.cfg\"! ~n", [node()]),
			exit(invalid_config);
		_ ->
			case lists:keyfind(node(), 2, ConnNodes) of
				false ->
					?CRITICAL_MSG("Start conn node[~p] failed: node name is not in the "
								  "configuration conn node list, please "
								  "check \"emobile.cfg\"! ~n", [node()]),
					exit(invalide_node_name);
				{{Ip, Port}, _} -> {ok, {Ip, Port}}
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
check_local_offline_msgs() ->
	F = fun(#undelivered_msgs{id = Id, 
							  mobile_id = MobileId,
							  timestamp = TimeStamp,
							  msg_bin = SendBin,
							  control_node = CtlNode}, DeleteList) ->
				case net_adm:ping(CtlNode) of
					pong ->
						mobile_network:deliver_message([MobileId], TimeStamp, SendBin),
						[Id | DeleteList];
					pang ->
						DeleteList
				end
		end,
	
	DList = db_ext:dirty_foldl(F, [], undelivered_msgs),
	
	case DList of
		[] -> ok;
		_ ->
			
			FD = fun(Id) ->	 mnesia:delete({undelivered_msgs, Id}) end,
			
			case mnesia:transaction(fun() -> lists:foreach(FD, DList) end) of
				{atomic, _} -> ok;
				{aborted, Reason} ->
					?ERROR_MSG("Delete record from local undelivered_msgs table failed: ~p ~n", [Reason]),
					{error, Reason}
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
notify_lb_svr_startup(ListenAddr) ->
	LbNodes = emobile_config:get_option(emlb_nodes),
	F = fun({_, LbNode}) ->
				case net_adm:ping(LbNode) of
					pong ->
						rpc:call(LbNode, service_load_balance, add_active_conn_node, {node(), ListenAddr});
					pang ->
						{error, "LB node is down"}
				end
		end,
	lists:foreach(F, LbNodes).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
notify_lb_svr_shutdown() ->
	LbNodes = emobile_config:get_option(emlb_nodes),
	F = fun({_, LbNode}) ->
				case net_adm:ping(LbNode) of
					pong ->
						rpc:call(LbNode, service_load_balance, remove_conn_node, node());
					pang ->
						{error, "LB node is down"}
				end
		end,
	lists:foreach(F, LbNodes).
