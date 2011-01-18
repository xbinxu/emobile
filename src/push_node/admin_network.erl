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

-export([process_received_msg/2]).

-record(undelivered_msgs, {id = 0, mobile_id = 0, msg_bin = <<>>, control_node}).

%%
%% API Functions
%%

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
	case MsgType of
		?MSG_PING  -> on_msg_ping();
		?MSG_LOGIN -> on_msg_login(MsgBody);
		?MSG_DELIVER -> on_msg_deliver(MsgSize, MsgBody);
		?MSG_BROADCAST -> on_msg_broadcast(MsgBody);
		_ -> ?ERROR_MSG("receive unkown message: ~p ~p ~p ~n", [MsgSize, MsgType, MsgBody])
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_msg_login(MsgBody) ->
	<<ServerId: 4/?NET_ENDIAN-unit:8, _/binary>> = MsgBody,	
	?INFO_MSG("Admin ~p logined. ~n", [ServerId]),
	put(server_id, ServerId),
	ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% keep connection heart-beat 
on_msg_ping() ->
	ServerId = case get(server_id) of
				   undefined -> 0;
				   Val -> Val
			   end,
	?INFO_MSG("Admin ~p ping. ~n", [ServerId]),
	MsgPing = <<8: 2/?NET_ENDIAN-unit:8, ?MSG_PING: 2/?NET_ENDIAN-unit:8, ServerId:4/?NET_ENDIAN-unit:8>>,
	self() ! {tcp_send, MsgPing},
	ok.

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
			MsgContentBin = binary:part(MsgBody, 16 + TargetNum * 4, byte_size(MsgBody) - (16 + TargetNum * 4)),

			?INFO_MSG("Receive message deliver,  ~p -> ~p: ~p  ~n", [SrcMobileId, TargetList, MsgContentBin]),

			deliver_message(TargetList, <<MsgSize:2/?NET_ENDIAN-unit:8,
										  ?MSG_DELIVER:2/?NET_ENDIAN-unit:8,
										  SrcMobileId:4/?NET_ENDIAN-unit:8,
										  TimeStampBin/binary, 												  
										  TargetNum: 4/?NET_ENDIAN-unit:8,
										  TargetListBin/binary,
										  MsgContentBin/binary>>),
			ok
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
deliver_message(TargetList, MsgBin) ->
	F = fun(MobileId) ->
				case ctlnode_selector:get_ctl_node(MobileId) of
					undefined ->
						send_by_backup(undefined, MobileId, MsgBin);
					CtlNode ->
						case rpc:call(CtlNode, service_lookup_mobile_node, lookup_conn_node, [MobileId]) of
							undefined ->
								save_undelivered_message(MobileId, MsgBin, CtlNode);
							{badrpc, Reason} ->
								?ERROR_MSG("RPC control node failed:~p for mobile: ~p, trying route by backup node.~n", [Reason, MobileId]),
								send_by_backup(CtlNode, MobileId, MsgBin);
							{ConnNode, _Pid} ->
								rpc_send_message(ConnNode, CtlNode, MobileId, MsgBin)
						end
				end
		end,
	lists:foreach(F, TargetList),
	ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
send_by_backup(CtlNode, MobileId, MsgBin) ->
	BackCtlNode = ctlnode_selector:get_ctl_back_node(MobileId), %% this call should never failed(result =/= undefined)
	case rpc:call(BackCtlNode, service_lookup_mobile_node, lookup_conn_node_backup, [MobileId]) of
		undefined -> 
			?ERROR_MSG("Lookup conn node failed and no control node config for mobile: ~p, message will be lost.~n", [MobileId]),
			save_undelivered_message(MobileId, MsgBin, CtlNode);
		{badrpc, Reason} ->
			?ERROR_MSG("RPC backup control node failed:~p.~n", [Reason]),
			save_undelivered_message(MobileId, MsgBin, CtlNode);										
		{ConnNode, _Pid} -> 
			rpc_send_message(ConnNode, undefined, MobileId, MsgBin)
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
rpc_send_message(ConnNode, CtlNode, MobileId, MsgBin) ->
	case rpc:call(ConnNode, service_mobile_conn, send_message, [CtlNode, MobileId, MsgBin]) of
		ok -> ok;
		{badrpc, Reason} ->
			?ERROR_MSG("RPC send message failed:~p for mobile: ~p, save undelivered message.~n", [Reason, MobileId]),
			save_undelivered_message(MobileId, MsgBin, CtlNode);
		{error, Reason} ->
			?ERROR_MSG("RPC send message failed:~p for mobile: ~p, save undelivered message.~n", [Reason, MobileId]),
			save_undelivered_message(MobileId, MsgBin, CtlNode)
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
save_undelivered_message(MobileId, MsgBin, CtlNode) ->
	case CtlNode of
		undefined -> {error, "message lost"}; %% abandon message when control node is not configured
		_ -> 
			case rpc:call(CtlNode, service_offline_msg, save_undelivered_msg, [MobileId, MsgBin]) of
				ok -> ok;
				{error, Reason} ->
					?ERROR_MSG("Save undelivered message to control node[~p] failed:~p , save it to local. ~n", [CtlNode, Reason]),
					save_local_undelivered_msg(MobileId, MsgBin, CtlNode);
				{badrpc, Reason} ->
					?ERROR_MSG("Save undelivered message to control node[~p] failed:~p, save it to local. ~n", [CtlNode, Reason]),
					save_local_undelivered_msg(MobileId, MsgBin, CtlNode)
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
save_local_undelivered_msg(MobileId, MsgBin, CtlNode) ->
	case CtlNode of
		undefined -> {error, "message lost"};
		_ ->
			Id = mnesia:dirty_update_counter(unique_ids, undelivered_msg, 1),
			Record = #undelivered_msgs{id = Id, mobile_id = MobileId, msg_bin = MsgBin, control_node = CtlNode},
			case mnesia:transaction(fun() -> mnesia:write(Record) end) of
				{atomic, ok} ->
					ok;
				{aborted, Reason} ->
					?CRITICAL_MSG("Save undelivered message to local database failed: ~p ~n", [Reason]),
					{error, "Database failed"}
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
on_msg_broadcast(MsgBody) ->
	<<Type: 2/?NET_ENDIAN-unit:8,
	  ServerId: 4/?NET_ENDIAN-unit:8,
	  _TimeStamp: 8/binary,
	  Txt/binary>> = MsgBody,
	
	TimeStampBin = emobile_message:make_timestamp_binary(),

	case Type of
		?BROADCAST_ALL -> 
			?INFO_MSG("Receive message broadcast all, ServerID: ~p Txt: ~p ~n", [ServerId, Txt]),
			ok; %% TODO: read client ids from db server
		?BROADCAST_ONLINE ->
			?INFO_MSG("Receive message broadcast online, ServerID: ~p Txt: ~p ~n", [ServerId, Txt]),
			service_broadcast:broadcast_online(ServerId, TimeStampBin, Txt);
		_ ->
			?ERROR_MSG("Receive invalide message from push[~p]: unkown broadcast type, kick out connection. ~n", [get(server_id)]),
			self() ! {kick_out, "unkown broadcast type"},
			{error, "unkown broadcast type"}
	end.




%%
%% Local Functions
%%

