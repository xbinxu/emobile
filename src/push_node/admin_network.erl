%% Author: Administrator
%% Created: 2011-1-18
%% Description: TODO: Add description to admin_network
-module(admin_network).

%%
%% Include files
%%

-include("message_define.hrl").
-include("loglevel.hrl").

%%
%% Exported Functions
%%

-export([tcp_send/4, process_received_msg/2, deliver_message/3]).

-record(undelivered_msgs, {id = 0, mobile_id = 0, timestamp, msg_bin = <<>>, control_node}).

%%
%% API Functions
%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
tcp_send(CtlNode, Socket, TimeStamp, SendBin) ->
	case get(server_id) of 
		undefined -> {error, "Mobile not login"};
		ServerId -> 
			case gen_tcp:send(Socket, SendBin) of
				ok -> ok;
				{error, Reason} ->
					save_undelivered_message(ServerId, TimeStamp, SendBin, CtlNode),
					{error, Reason}
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Bin: received binary data
%% Fun: Fun(MsgSize(ushort), MsgType(ushort), MsgBody(binary))
process_received_msg(Socket, Bin) when is_binary(Bin) ->
	case Bin of
		<<MsgSize:2/?NET_ENDIAN-unit:8, MsgType:2/?NET_ENDIAN-unit:8, Extra/binary>> ->
			case MsgSize =< ?MAX_MSG_SIZE of
				true ->
					MsgBodySize = MsgSize - 4,
					case Extra of
						<<MsgBody:MsgBodySize/binary, Rest/binary>> ->
							on_receive_msg(MsgSize, MsgType, MsgBody), %% call funcion that handles client messages
							process_received_msg(Socket, Rest);
						<<_/binary>> ->
							{ok, Bin}
					end;
				false ->
					?ERROR_MSG("receive unkown message: ~p ~p ~p ~n", [MsgSize, MsgType, Extra]),
					self() ! {kick_out, "invalid message length"},
					{error, <<>>}
			end;
		
		<<_SomeBin/binary>> ->
			{ok, Bin}
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_receive_msg(MsgSize, MsgType, MsgBody) ->
	?INFO_MSG("Receive message: ~p ~n ~p ~n", [MsgType, MsgBody]),
	case MsgType of
		?MSG_PING  -> on_msg_ping(MsgSize);
		?MSG_LOGIN -> on_msg_login(MsgBody);
		?MSG_DELIVER -> on_msg_deliver(MsgSize, MsgBody);
		?MSG_BROADCAST -> on_msg_broadcast(MsgBody);
		?MSG_LOOKUP_CLIENT -> on_msg_lookupclient(MsgBody);
		_ -> 
			?ERROR_MSG("receive unkown message: ~p ~p ~p ~n", [MsgSize, MsgType, MsgBody]),
			self() ! {kick_out, "receive unkown message"}
	end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% server login
on_msg_login(MsgBody) ->
	<<ServerId: 4/?NET_ENDIAN-unit:8, _/binary>> = MsgBody,
	case ctlnode_selector:get_ctl_node(ServerId) of
		undefined -> 
			?ERROR_MSG("configure control node for server[~p] not found, trying login to backup "
			           "control node. ~n", [ServerId]),
			login_backup_control_node(ServerId);
		CtlNode when is_atom(CtlNode) ->
			case rpc:call(CtlNode, service_lookup_mobile_node, on_mobile_login, [ServerId, erlang:node(), self()], infinity) of
				ok -> 
					on_login_ctlnode_success(CtlNode, ServerId);
				{badrpc, Reason} -> 
					?ERROR_MSG("Login mobile[~p] to control node[~p] failed: ~p, trying login to ""
                               backup control node! ~n", [ServerId, CtlNode, Reason]),
                    login_backup_control_node(ServerId);
				{error, Reason} ->
					?ERROR_MSG("Login mobile[~p] to control node[~p] failed: ~p, close connection", [ServerId, CtlNode, Reason]),		
					exit(login_error)
			end			
	end.	

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
login_backup_control_node(ServerId) ->
	BackCtlNode = ctlnode_selector:get_ctl_back_node(ServerId),
	case rpc:call(BackCtlNode, service_lookup_mobile_node, on_mobile_login, [ServerId, erlang:node(), self()]) of
		ok -> 
			on_login_ctlnode_success(undefined, ServerId);
		{badrpc, Reason} -> 
			?CRITICAL_MSG("Login server[~p] to backup control node[~p] failed:~p, no way to rescue, "
			              "kickout it! ~n", [ServerId, BackCtlNode, Reason]),
			self() ! {kick_out, "No control node available."},
			ok
	end.	

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_login_ctlnode_success(_CtlNode, ServerId) ->
	?INFO_MSG("Mobile[~p] logined. ~n", [ServerId]),			
	put(server_id, ServerId),
	ok.	

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% keep connection heart-beat 
on_msg_ping(MsgSize) ->
	case MsgSize of
		8 -> 
			ServerId = case get(server_id) of
						   undefined -> 0;
						   Val -> Val
					   end,
			MsgPing = <<8: 2/?NET_ENDIAN-unit:8, ?MSG_PING: 2/?NET_ENDIAN-unit:8, ServerId:4/?NET_ENDIAN-unit:8>>,
			self() ! {tcp_send_ping, MsgPing},
			ok;
		_ ->
			self() ! {kick_out, "invalid msg PING"},
			{error, invalide_msg_ping}
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% client request deliver message to other client(s)
on_msg_deliver(MsgSize, MsgBody) -> 
	<<SrcMobileId:4/?NET_ENDIAN-unit:8, 
	  _TimeStamp:8/binary, 
      TargetNum: 4/?NET_ENDIAN-unit:8>> = binary:part(MsgBody, 0, 16),

	case TargetNum of
		0 -> ok;
		_ ->
			TargetListBin = binary:part(MsgBody, 16, TargetNum * 4),
			TargetList = emobile_message:decode_target_list(TargetListBin, TargetNum, []),
			
			TimeStampBin = emobile_message:make_timestamp_binary(),
			TimeStamp    = emobile_message:decode_timestamp(TimeStampBin),
			MsgContentBin = binary:part(MsgBody, 16 + TargetNum * 4, byte_size(MsgBody) - (16 + TargetNum * 4)),

			?INFO_MSG("Receive message deliver,  ~p -> ~p: ~p  ~n", [SrcMobileId, TargetList, MsgContentBin]),

			ResultL = deliver_message(TargetList, 
                            		  TimeStamp,
                                      <<MsgSize:2/?NET_ENDIAN-unit:8,
			   			              ?MSG_DELIVER:2/?NET_ENDIAN-unit:8,
							          SrcMobileId:4/?NET_ENDIAN-unit:8,
							          TimeStampBin/binary, 												  
							          TargetNum: 4/?NET_ENDIAN-unit:8,
							          TargetListBin/binary,
							          MsgContentBin/binary>>),

			FSndResult = fun({MobileId, Result}, Bin) ->
						      <<Result: 2/?NET_ENDIAN-unit:8,
                                MobileId: 4/?NET_ENDIAN-unit:8,
                                Bin/binary>>	    
                         end,

            ResultBin = lists:foldl(FSndResult, <<>>, ResultL),

            MsgLeng = erlang:byte_size(ResultBin) + 6,

            %% send back message result
            self() ! {tcp_send_ping, <<MsgLeng: 2/?NET_ENDIAN-unit:8,
                                       ?MSG_RESULT: 2/?NET_ENDIAN-unit:8,
                                       ?MSG_DELIVER: 2/?NET_ENDIAN-unit:8,
                                       ResultBin/binary>>}
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
deliver_message(TargetList, TimeStamp, MsgBin) ->
	F = fun(MobileId, L) ->
				Result = case ctlnode_selector:get_ctl_node(MobileId) of
					undefined ->
						send_by_backup(undefined, MobileId, TimeStamp, MsgBin);
					CtlNode ->
						case rpc:call(CtlNode, service_lookup_mobile_node, lookup_conn_node, [MobileId]) of
							undefined ->
								save_undelivered_message(MobileId, TimeStamp, MsgBin, CtlNode);
							{badrpc, Reason} ->
								?ERROR_MSG("RPC control node failed:~p for mobile: ~p, trying route by backup node.~n", [Reason, MobileId]),
								send_by_backup(CtlNode, MobileId, TimeStamp, MsgBin);
							{ConnNode, Pid} ->
								rpc_send_message(ConnNode, CtlNode, MobileId, Pid, TimeStamp, MsgBin)
						end
				end,
				[{MobileId, Result} | L]
		end,
	lists:foldl(F, [], TargetList).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
send_by_backup(CtlNode, MobileId, TimeStamp, MsgBin) ->
	BackCtlNode = ctlnode_selector:get_ctl_back_node(MobileId), %% this call should never failed(result =/= undefined)
	case rpc:call(BackCtlNode, service_lookup_mobile_node, lookup_conn_node_backup, [MobileId]) of
		undefined -> 
			?ERROR_MSG("Lookup conn node failed and no control node config for mobile: ~p, message will be lost.~n", [MobileId]),
			save_undelivered_message(MobileId, TimeStamp, MsgBin, CtlNode);
		{badrpc, Reason} ->
			?ERROR_MSG("RPC backup control node failed:~p.~n", [Reason]),
			save_undelivered_message(MobileId, TimeStamp, MsgBin, CtlNode);										
		{ConnNode, Pid} -> 
			rpc_send_message(ConnNode, undefined, MobileId, Pid, TimeStamp, MsgBin)
	end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
rpc_send_message(ConnNode, CtlNode, MobileId, Pid, TimeStamp, MsgBin) ->
	case rpc:call(ConnNode, service_mobile_conn, send_message, [CtlNode, Pid, TimeStamp, MsgBin]) of
		ok -> ?SEND_OK;
		{badrpc, Reason} ->
			?ERROR_MSG("RPC send message failed:~p for mobile: ~p, save undelivered message.~n", [Reason, MobileId]),
			save_undelivered_message(MobileId, TimeStamp, MsgBin, CtlNode);
		{error, Reason} ->
			?ERROR_MSG("RPC send message failed:~p for mobile: ~p, save undelivered message.~n", [Reason, MobileId]),
			save_undelivered_message(MobileId, TimeStamp, MsgBin, CtlNode)
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
save_undelivered_message(MobileId, TimeStamp, MsgBin, CtlNode) ->
	case CtlNode of
		undefined -> {error, "message lost"}; %% abandon message when control node is not configured
		_ -> 
			case rpc:call(CtlNode, service_offline_msg, save_undelivered_msg, [MobileId, TimeStamp, MsgBin]) of
				ok -> ?MSG_SAVED_CTL;
				{error, Reason} ->
					?ERROR_MSG("Save undelivered message to control node[~p] failed:~p , save it to local. ~n", [CtlNode, Reason]),
					save_local_undelivered_msg(MobileId, TimeStamp, MsgBin, CtlNode);
				{badrpc, Reason} ->
					?ERROR_MSG("Save undelivered message to control node[~p] failed:~p, save it to local. ~n", [CtlNode, Reason]),
					save_local_undelivered_msg(MobileId, TimeStamp, MsgBin, CtlNode)
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
save_local_undelivered_msg(MobileId, TimeStamp, MsgBin, CtlNode) ->
	case CtlNode of
		undefined -> ?MSG_LOST;
		_ ->
			Id = mnesia:dirty_update_counter(unique_ids, undelivered_msg, 1),
			Record = #undelivered_msgs{id=Id, mobile_id=MobileId, timestamp=TimeStamp, msg_bin=MsgBin, control_node=CtlNode},
			case mnesia:transaction(fun() -> mnesia:write(Record) end) of
				{atomic, ok} ->
					?MSG_SAVED_LOCAL;
				{aborted, Reason} ->
					?CRITICAL_MSG("Save undelivered message to local database failed: ~p ~n", [Reason]),
					?MSG_LOST
			end
	end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_msg_broadcast(MsgBody) ->
	<<Type: 2/?NET_ENDIAN-unit:8,
	  ServerId: 4/?NET_ENDIAN-unit:8,
	  _TimeStamp: 8/binary,
	  Txt/binary>> = MsgBody,

    %% send back message result
	self() ! {tcp_send_ping, <<12: 2/?NET_ENDIAN-unit:8,
                               ?MSG_RESULT: 2/?NET_ENDIAN-unit:8,
                               ?MSG_BROADCAST: 2/?NET_ENDIAN-unit:8,
                               0: 2/?NET_ENDIAN-unit:8,
                               0: 4/?NET_ENDIAN-unit:8>>},
	
	TimeStampBin = emobile_message:make_timestamp_binary(),

	case Type of
		?BROADCAST_ALL -> 
			?INFO_MSG("Receive message broadcast all, ServerID: ~p Txt: ~p ~n", [ServerId, Txt]),
			service_broadcast:broadcast_all(ServerId, TimeStampBin, Txt);
		?BROADCAST_ONLINE ->
			?INFO_MSG("Receive message broadcast online, ServerID: ~p Txt: ~p ~n", [ServerId, Txt]),
			service_broadcast:broadcast_online(ServerId, TimeStampBin, Txt);
		_ ->
			?ERROR_MSG("Receive invalide message from push[~p]: unkown broadcast type, kick out connection. ~n", [get(server_id)]),
			self() ! {kick_out, "unkown broadcast type"},
			{error, "unkown broadcast type"}
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_msg_lookupclient(MsgBody) ->
	<<MobileId: 4/?NET_ENDIAN-unit:8, _/binary>> = MsgBody,
	?INFO_MSG("request to lookup client: ~p ", [MobileId]),
    Result = case ctlnode_selector:get_ctl_node(MobileId) of
			      undefined -> 101;
                  CtlNode ->
						?INFO_MSG("lookup from control node: ~p", [CtlNode]),
						case rpc:call(CtlNode, service_lookup_mobile_node, lookup_conn_node, [MobileId]) of
							undefined ->
								1;
							{badrpc, Reason} ->
								?ERROR_MSG("RPC control node failed:~p for mobile: ~p, trying route by backup node.~n", [Reason, MobileId]),
								1001;
							{_ConnNode, _Pid} -> 0
						end                  
			  end,

	?INFO_MSG("lookup result: ~p ~n", [Result]),

	self() ! {tcp_send_ping, <<12: 2/?NET_ENDIAN-unit:8,
                               ?MSG_RESULT: 2/?NET_ENDIAN-unit:8,
                               ?MSG_LOOKUP_CLIENT: 2/?NET_ENDIAN-unit:8,
                               Result: 2/?NET_ENDIAN-unit:8,
                               MobileId: 4/?NET_ENDIAN-unit:8>>},
	ok.

%%
%% Local Functions
%%

