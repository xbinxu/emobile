%%% -------------------------------------------------------------------
%%% Author  : xuxb
%%% Description : push messages to mobile client
%%%
%%% Created : 2010-12-31
%%% -------------------------------------------------------------------

-module(service_push_msg).

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

-include("loglevel.hrl").
-include("message_define.hrl").

%% --------------------------------------------------------------------
%% External exports
-export([start_link/0, on_ctlnode_startup/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {}).

-record(unique_ids, {type, id}).
-record(undelivered_msgs, {id = 0, mobile_id = 0, msg_bin = <<>>, control_node}).


-define(TCP_SERVER_NAME, 'MESSAGE PUSH TCP INTERFACE').

%% ====================================================================
%% External functions
%% ====================================================================


%% ====================================================================
%% Server functions
%% ====================================================================

%% --------------------------------------------------------------------
%% Function: start_link/0
%% Description: start message push tcp interface server(called from supervisor)
%% Returns: {ok, Pid} -> ok
%%          _         -> error
%% --------------------------------------------------------------------
start_link() ->
	case gen_server:start_link({local, ?MODULE}, ?MODULE, [], []) of
		{ok, Pid} ->
			{ok, Pid};
		Result ->
			?CRITICAL_MSG("Start message push server service failed: ~p ~n", [Result]),
			Result
	end.

%% --------------------------------------------------------------------
%% Function: start_link/0
%% Description: RPC called from control node, synchronize offline messages
%% Returns: ok
%% --------------------------------------------------------------------
on_ctlnode_startup(CtlNode) ->
	gen_server:cast(?MODULE, {check_local_offline_msgs, CtlNode}). %% synchronize offline messages

%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
init([]) ->
	{ok, {Ip, Port}} = check_emobile_configuration(),	
	?INFO_MSG("env setting: Ip[~p] Port[~p] ~n", [Ip, Port]),	
	
	mnesia:create_table(unique_ids, 
						[{disc_copies, [node()]},
						 {attributes, record_info(fields, unique_ids)}]),		
	
	mnesia:create_table(undelivered_msgs,
						[{disc_copies, [node()]},
						 {attributes, record_info(fields, undelivered_msgs)},
						 {index, [control_node]}]),		
	
	AdminList = emobile_config:get_option(admin_list),
	?INFO_MSG("configuration setting: AdminList: ~p ~n", [AdminList]),
	
	AdminAddrList = lists:map(fun(IpStr) -> {ok, Addr} = inet:getaddr(IpStr, inet), Addr end, AdminList),	
	
	FHandlePacket = fun(Sock) -> 
							inet:setopts(Sock, [binary, {packet, 0}, {active, once}]),
							case inet:peername(Sock) of
								{ok, {ConnAddr, _}} ->
									case lists:member(ConnAddr, AdminAddrList) of
										true ->					
											control_loop([Sock, <<>>]);
										false ->
											?CRITICAL_MSG("Admin connection from invalid ip[~p], close it!", [ConnAddr])
									end;
								_ ->
									?CRITICAL_MSG("Get admin connection ip failed, close admin connection!", [])
							end
					end, 	
	{ok, IpAddr} = inet:getaddr(Ip, inet),
	?INFO_MSG("listening ip: ~p ~n", [IpAddr]),	
	
	{ok, _} = socket_server:start(?TCP_SERVER_NAME, IpAddr, Port, FHandlePacket, fun(_, _) -> ok end),
	
	check_local_offline_msgs(),
	
    {ok, #state{}}.

%% --------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_cast({check_local_offline_msgs, CtlNode}, Server) ->
	case mnesia:dirty_index_read(undelivered_msgs, CtlNode, #undelivered_msgs.control_node) of
		[] ->
			void;
		L ->
			lists:foreach(fun(#undelivered_msgs{mobile_id=MobileId, msg_bin=MsgBin}) -> deliver_message([MobileId], MsgBin) end, L),
			lists:foreach(fun(#undelivered_msgs{id=Id}) -> mnesia:dirty_delete(undelivered_msgs, Id) end, L)
	end,
	{noreply, Server};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, _State) ->
	socket_server:stop(?TCP_SERVER_NAME),
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% --------------------------------------------------------------------
%%% Internal functions
%% --------------------------------------------------------------------
check_emobile_configuration() ->
	PushNodes = emobile_config:get_option(empush_nodes),
	CtlBackNodes = emobile_config:get_option(emctl_back_nodes),	
	
	?INFO_MSG("PushNodes: ~p ~n", [PushNodes]),
	
	case length(CtlBackNodes) of
		0 -> 
			?CRITICAL_MSG("Start push node[~p] failed: you should config at least ONE "
						  "control backup node, please check \"emobile.cfg\"! ~n", [node()]),
			exit(invalid_config);
		_ ->
			case lists:keyfind(node(), 2, PushNodes) of
				false ->
					?CRITICAL_MSG("Start push node[~p] failed: node name is not in the "
								  "configuration push node list, please "
								  "check \"emobile.cfg\"! ~n", [node()]),
					exit(invalide_node_name);
				{{Ip, Port}, _} -> 
					{ok, {Ip, Port}}
			end
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
control_loop([Socket, LastMsg]) ->
	receive
		{tcp, Socket, Bin} ->
			?INFO_MSG("Receive binary: ~p ~n", [Bin]),
			{ok, LastMsg1} = process_received_msg(Socket, <<LastMsg/binary, Bin/binary>>),
			inet:setopts(Socket, [{active, once}]),
			erlang:garbage_collect(self()),
			control_loop([Socket, LastMsg1]);			
		
		{tcp_closed, Socket} ->
			erlang:garbage_collect(self());
	
		{tcp_send, SendBin} ->
			case gen_tcp:send(Socket, SendBin) of
				ok ->
					erlang:garbage_collect(self()),
					control_loop([Socket, LastMsg]);
				
				{error, Reason} ->
					?ERROR_MSG("Send tcp data to admin client failed: ~p. ~n", [Reason]),
					erlang:garbage_collect(self())
			end;

		Other ->
			?ERROR_MSG("Admin connection process receive unkown message: ~p, ignore it. ~n", [Other]),
			control_loop([Socket, LastMsg])
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
			TargetList = decode_target_list(TargetListBin, TargetNum, []),
			
			TimeStampBin = make_timestamp_binary(),
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
make_timestamp_binary() ->
	{{Year, Month, Day}, {Hour, Min, Sec}} = calendar:local_time(),
	<<Year: 2/?NET_ENDIAN-unit:8, 
	  Month: 1/?NET_ENDIAN-unit:8, 
	  Day: 1/?NET_ENDIAN-unit:8, 
	  0: 1/?NET_ENDIAN-unit:8,
	  Hour: 1/?NET_ENDIAN-unit:8, 
	  Min: 1/?NET_ENDIAN-unit:8, 
	  Sec: 1/?NET_ENDIAN-unit:8>>.	
	

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
decode_target_list(_, 0, L) ->
	L;
decode_target_list(<<TargetId:4/?NET_ENDIAN-unit:8, Bin/binary>>, TargetNum, L) ->
	decode_target_list(Bin, TargetNum - 1, [TargetId | L]).

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
	
	TimeStampBin = make_timestamp_binary(),

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


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
check_local_offline_msgs() ->
	F = fun(#undelivered_msgs{id = Id, 
							  mobile_id = MobileId,
							  msg_bin = SendBin,
							  control_node = CtlNode}, DeleteList) ->
				case net_adm:ping(CtlNode) of
					pong ->
						deliver_message([MobileId], SendBin),
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




