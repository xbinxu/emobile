%%% Author: xuxb
%%% Created: 2010-4-28
%%% Description: Control server running on control node
%%% Copyright (c) 2010 www.nd.com.cn

-module(service_lookup_mobile_node).
-behaviour(gen_server).


%%
%% Include files
%%

-include("loglevel.hrl").
-include("message_define.hrl").

%%
%% Exported Functions
%%

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([start_link/0]).

-export([on_mobile_login/3,
		 on_mobile_logout/3,
		 on_conn_node_down/1,
		 lookup_conn_node/1,
		 lookup_conn_node_backup/1,
		 broadcast_all/3
		 ]).

%%
%% API Functions
%%

-record(server, {node_type}).
-record(mobile_node, {mobile_id, conn_node, pid}).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_link() ->
	case gen_server:start_link({local, ?MODULE}, ?MODULE, [], []) of
		{ok, Pid} ->
			{ok, Pid};
		Result ->
			?CRITICAL_MSG("Start gateway server service failed: ~p ~n", [Result]),
			Result
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_mobile_login(MobileId, ConnNode, Pid) ->
	case mnesia:transaction(fun() -> login_transaction(MobileId, ConnNode, Pid) end) of
		{atomic, ok} -> ok;
		{aborted, Reason} -> {error, Reason}
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_mobile_logout(MobileId, ConnNode, Pid) ->
	case mnesia:transaction(fun() ->
									case mnesia:read(mobile_node, MobileId) of
										[#mobile_node{mobile_id=MobileId, conn_node=ConnNode, pid=Pid}] ->
											mnesia:delete({mobile_node, MobileId});
										_ ->
											ok
									end
							end) of
		{atomic, ok} -> ok;
		{aborted, Reason} -> {error, Reason}
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_conn_node_down(ConnNode) ->
	case mnesia:transaction(fun() -> delete_conn_node(ConnNode) end) of
		{atomic, ok} -> ok;
		{aborted, Reason} -> {error, Reason}
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% when worked as nomal ctl node
lookup_conn_node(MobileId) ->
	case mnesia:transaction(fun() -> lookup_transaction(MobileId) end) of
		{atomic, Result} -> 
			Result;
		{aborted, Reason} -> 
			?ERROR_MSG("lookup connection node for mobile[~p] failed: ~p ~n", [MobileId, Reason]),
			undefined
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% when worked as backup ctl node
lookup_conn_node_backup(MobileId) ->
	case mnesia:transaction(fun() -> mnesia:read(mobile_node, MobileId) end) of
		{atomic, [#mobile_node{mobile_id=MobileId, conn_node=ConnNode, pid=Pid}]} -> {ConnNode, Pid};
		{atomic, []} -> undefined;
		{aborted, Reason} ->
			?ERROR_MSG("Read mnesia table[mobile_node] failed: ~p ~n", [Reason]),
			undefined
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% broadcast all
broadcast_all(From, TimeStampBin, MsgBin) ->
	{_, _, _, _, SQL} = emobile_config:get_option(account_db),
	ConnNodes = emobile_config:get_option(emctl_nodes),
	case lists:keyfind(node(), 3, ConnNodes) of
		{StartUID, EndUID, _} ->
			ReadSQL = lists:flatten(io_lib:format(SQL, [StartUID, EndUID])),
			broadcast_all_impl(From, TimeStampBin, MsgBin, ReadSQL, 0);
		false ->
			?ERROR_MSG("Can't get uid scope from emobile.cfg, please check it! ~n", []),
			{error, "check emobile.cfg"}
	end.
						
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init([]) ->
	process_flag(trap_exit, true), 
	
	mnesia:create_table(mobile_node, 
						[{ram_copies, [node()]},
						 {attributes, record_info(fields, mobile_node)},
						 {index, [conn_node]}]),	
	
	{ok, NodeType} = check_emobile_configuration(),
	
	notify_conn_node_startup(),
	notify_push_node_startup(),
	
	{ok, #server{node_type = NodeType}}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
terminate(_Reason, _Server) ->
	ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% handle_cast({on_mobile_logout, MobileId, _Node}, Server) ->
%% 	ets:delete(ets_mobile_id2node, MobileId),
%% 	{noreply, Server};
%% 
%% handle_cast({on_conn_node_down, Node}, Server) ->
%% 	?INFO_MSG("Node[~p] is reset! ~n", [Node]),
%% 	ets:match_delete(ets_mobile_id2node, {'_', Node}),
%% 	{noreply, Server};

handle_cast(Event, Server) ->
	?INFO_MSG("receive event: ~p ~n", [Event]),
	{noreply, Server}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% handle_call({on_mobile_login, MobileId, Node}, _From, Server) ->
%% 	?INFO_MSG("on_mobile_login(~p, ~p) ~n", [MobileId, Node]),
%% 	case ets:lookup(ets_mobile_id2node, MobileId) of
%% 		[{MobileId, OrigConnNode}] ->
%% 			?INFO_MSG("Mobile[~p] has logined to ~p, kickout it! ~n", [MobileId, OrigConnNode]),
%% 			case rpc:call(OrigConnNode, service_mobile_conn, kickout_mobile, [MobileId, "re-login"]) of
%% 				ok -> 
%% 					ets:delete(ets_mobile_id2node, MobileId),
%% 					ets:insert(ets_mobile_id2node, {MobileId, Node});
%% 				{badrpc, Reason} -> 
%% 					?CRITICAL_MSG("RPC call to node[~p] failed: ~p, reset this node. ~n", [OrigConnNode, Reason]),
%% 					gen_server:cast(?MODULE, {on_conn_node_down, OrigConnNode})
%% 			end;
%% 		_ ->
%% 			ets:insert(ets_mobile_id2node, {MobileId, Node})
%% 	end,
%% 	{reply, ok, Server};

handle_call(_Request, _From, Server) ->
	{reply, ok, Server}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
handle_info(Info, Server) ->
	?INFO_MSG("Mobile push server receive info: ~p ~n", [Info]),
	{noreply, Server}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
code_change(_OldVsn, Server, _Extra) ->
	{ok, Server}.


%%
%% Local Functions
%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% check emobile cfg, session emctl_nodes
check_emobile_configuration() ->
	CtlNodes = emobile_config:get_option(emctl_nodes),
	CtlBackNodes = emobile_config:get_option(emctl_back_nodes),	
	
	case length(CtlBackNodes) of
		0 -> 
			?CRITICAL_MSG("Start control node[~p] failed: you should config at least ONE "
							  "control backup node, please check \"emobile.cfg\"! ~n", [node()]),
			exit(invalid_config);
		_ ->
			case lists:keysearch(node(), 3, CtlNodes) of
				false ->
					case lists:member(node(), CtlBackNodes) of
						false ->
							?CRITICAL_MSG("Start control node failed: node name[~p] is not in the "
											  "configuration control and back control list, please "
												  "check \"emobile.cfg\"! ~n", [node()]),
							exit(invalide_node_name);
						true ->	{ok, backup}
					end;
				{value, {_MobileId_s, _MobileId_e, _NodeName}} -> {ok, normal}
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% write record to mnesia table  
%% IMPORTANT: this function must run in a mnesia transaction
write_mobile_node(MobileId, ConnNode, Pid) ->
%% 	?INFO_MSG("write ~p <-> {~p, ~p} to mnesia database. ~n", [MobileId, ConnNode, Pid]),
	case mnesia:write(#mobile_node{mobile_id=MobileId, conn_node=ConnNode, pid = Pid}) of
		ok -> 
			ok;
		{aborted, Reason} ->
			?ERROR_MSG("Write to mnesia table[mobile_node] failed: ~p ~n", [Reason]),
			mnesia:abort(Reason)
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% process login transaction  
%% IMPORTANT: this function must run in a mnesia transaction
login_transaction(MobileId, ConnNode, Pid) ->
	case mnesia:read(mobile_node, MobileId) of
		[#mobile_node{mobile_id = MobileId, conn_node = OrigConnNode, pid = OrigPid}] ->			
			?INFO_MSG("Mobile[~p] has logined to ~p, kickout it! ~n", [MobileId, OrigConnNode]),
			case rpc:call(OrigConnNode, service_mobile_conn, kickout_mobile, [MobileId, OrigPid, "re-login"]) of
				ok -> 
					write_mobile_node(MobileId, ConnNode, Pid);
				{badrpc, Reason} -> 
					?ERROR_MSG("RPC call to node[~p] failed: ~p, reset this node. ~n", [OrigConnNode, Reason]),
					write_mobile_node(MobileId, ConnNode, Pid),
					gen_server:cast(?MODULE, {on_conn_node_down, OrigConnNode})
			end;
		
		[] ->
%% 			?INFO_MSG("no node for mobile: ~p, directly login. ~n", [MobileId]),
			write_mobile_node(MobileId, ConnNode, Pid);
		
		{aborted, Reason} ->
			?ERROR_MSG("read from mnesia table[mobile_node] failed: ~p ~n", [Reason]),
			mnesia:abort(Reason)	
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% process lookup transaction  
%% IMPORTANT: this function must run in a mnesia transaction
lookup_transaction(MobileId) ->
	case mnesia:read(mobile_node, MobileId) of
		[#mobile_node{mobile_id = MobileId, conn_node = ConnNode, pid=Pid}] -> 
			{ConnNode, Pid};
		[] -> 
			case ctlnode_selector:get_ctl_back_node(MobileId) of
				undefined -> 
					undefined;
				BackCtlNode -> 
					case rpc:call(BackCtlNode, service_lookup_mobile_node, lookup_conn_node_backup, [MobileId]) of
						undefined -> 
							undefined;
						{badrpc, Reason} -> 
							?ERROR_MSG("rpc call backup control node to lookup conn node for mobile[~p] failed: ~p ~n", [MobileId, Reason]),
							undefined;
						{Node, Pid} -> 
							%% insert mobileid<->conn_node to ets table
							write_mobile_node(MobileId, Node, Pid),
							{Node, Pid}
					end
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% delete records of connection node
%% IMPORTANT: this function must run in a mnesia transaction
delete_conn_node(ConnNode) ->
	case mnesia:index_read(mobile_node, ConnNode, #mobile_node.conn_node) of
		[] -> ok;
		{aborted, Reason} -> mnesia:abort(Reason);
		L -> 
			lists:foreach(fun(#mobile_node{mobile_id=MobileId}) ->
								  mnesia:delete({mobile_node, MobileId})
						  end, L),
			ok
	end.	

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% notify conn node this node is startup
notify_conn_node_startup() ->
	ConnNodes = emobile_config:get_option(emconn_nodes),
	F = fun({_, ConnNode}) ->
				case net_adm:ping(ConnNode) of
					pong ->
						rpc:cast(ConnNode, service_mobile_conn, on_ctlnode_startup, [node()]);
					pang ->
						void
				end
		end,
	lists:foreach(F, ConnNodes).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% notify push node this node is startup
notify_push_node_startup() ->
	PushNodes = emobile_config:get_option(empush_nodes),
	F = fun({_, PushNode}) ->
				case net_adm:ping(PushNode) of
					pong ->
						rpc:cast(PushNode, service_push_msg, on_ctlnode_startup, [node()]);
					pang ->
						void
				end
		end,
	lists:foreach(F, PushNodes).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
broadcast_all_impl(From, TimeStampBin, MsgBin, ReadSQL, Counter) ->
	case mysql:fetch(account_db, list_to_binary(ReadSQL)) of
		{data, {mysql_result, _, DataList, _, _}} ->
			UID_L = lists:map(fun(DataRow) -> lists:nth(1, DataRow) end, DataList),
			broadcast_uid_list(From, UID_L, TimeStampBin, MsgBin);
		Error ->
			?ERROR_MSG("fetch uid list from mysql db failed: ~p ~n", [Error]),
			case Counter > 120 of
				true ->
					{error, "fetch uid list failed"};
				false ->
					timer:sleep(59999),
					broadcast_all_impl(From, TimeStampBin, MsgBin, ReadSQL, Counter+1)
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
broadcast_uid_list(From, Uid_L, TimeStampBin, MsgBin) ->
	TimeStamp = emobile_message:decode_timestamp(TimeStampBin),
	F = fun(MobileId) ->
				MsgSize = 2+2+4+8+4+4+byte_size(MsgBin),
				MsgBin = <<MsgSize:2/?NET_ENDIAN-unit:8,
							?MSG_DELIVER:2/?NET_ENDIAN-unit:8,
							From:4/?NET_ENDIAN-unit:8,
							TimeStampBin/binary, 												  
							1: 4/?NET_ENDIAN-unit:8,
							MobileId: 4/?NET_ENDIAN-unit:8,
							MsgBin/binary>>,

				case mnesia:dirty_read(mobile_node, MobileId) of
					[#mobile_node{mobile_id=MobileId, conn_node=ConnNode, pid=Pid}] ->
						case rpc:call(ConnNode, service_mobile_conn, send_message, [node(), Pid, TimeStamp, MsgBin]) of
							ok -> ok;
							{badrpc, Reason} ->
								?ERROR_MSG("RPC send message failed:~p for mobile: ~p, save undelivered message.~n", [Reason, MobileId]),
								service_offline_msg:save_undelivered_msg(MobileId, TimeStamp, MsgBin);
							{error, Reason} ->
								?ERROR_MSG("RPC send message failed:~p for mobile: ~p, save undelivered message.~n", [Reason, MobileId]),
								service_offline_msg:save_undelivered_msg(MobileId, TimeStamp, MsgBin)
						end;
					[] ->
						service_offline_msg:save_undelivered_msg(MobileId, TimeStamp, MsgBin);
					{aborted, Reason} ->
						?CRITICAL_MSG("read mobile_node for mobile[~p] failed: ~p ~n", [MobileId, Reason]),
						service_offline_msg:save_undelivered_msg(MobileId, TimeStamp, MsgBin)
				end,
				timer:sleep(5)
		end,
	lists:foreach(F, Uid_L),
	ok.
	