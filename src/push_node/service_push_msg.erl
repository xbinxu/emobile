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
-record(undelivered_msgs, {id = 0, mobile_id = 0, timestamp, msg_bin = <<>>, control_node}).


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
											admin_loop:loop([Sock, <<>>]);
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
			lists:foreach(fun(#undelivered_msgs{mobile_id=MobileId, timestamp=TimeStamp, msg_bin=MsgBin}) -> 
								  admin_network:deliver_message([MobileId], TimeStamp, MsgBin) 
						  end, L),
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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
check_local_offline_msgs() ->
	F = fun(#undelivered_msgs{id = Id, 
							  mobile_id = MobileId,
							  timestamp = TimeStamp,
							  msg_bin = MsgBin,
							  control_node = CtlNode}, DeleteList) ->
				case net_adm:ping(CtlNode) of
					pong ->
						admin_network:deliver_message([MobileId], TimeStamp, MsgBin),
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




