%%% -------------------------------------------------------------------
%%% Author  : Administrator
%%% Description :
%%%
%%% Created : 2011-2-21
%%% -------------------------------------------------------------------
-module(service_load_balance).

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

-include("loglevel.hrl").
-include("message_define.hrl").

%% --------------------------------------------------------------------
%% External exports
-export([start_link/0, remove_conn_node/1]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {active_conn_nodes = [], node_index = 1}).

%% ====================================================================
%% External functions
%% ====================================================================

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_link() ->
	case gen_server:start_link({local, ?MODULE}, ?MODULE, [], []) of
		{ok, Pid} ->
			{ok, Pid};
		Result ->
			?CRITICAL_MSG("Start load balance server service failed: ~p ~n", [Result]),
			Result
	end.

remove_conn_node(Node) ->
	gen_server:call(?MODULE, {remove_conn_node, Node}).


%% ====================================================================
%% Server functions
%% ====================================================================

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
	
	FHandlePacket = fun(Sock) -> 
							inet:setopts(Sock, [binary, {packet, 0}, {active, once}]),
							loop([Sock, <<>>]) 
					end, 	
	
	FOnChildExit = fun(_Pid, _Why) -> void end,
	
	{ok, IpAddr} = inet:getaddr(Ip, inet), %% to confirm Ip is valid inet address
	{ok, _} = socket_server:start('LOAD BALANCE TCP SERVER', IpAddr, Port, FHandlePacket, FOnChildExit),	
	
	case emobile_config:get_option(emconn_nodes) of 
		[] -> {stop, bad_configuration};
		ConnNodes ->
			F = fun({{CIP, CPort}, Node}, AL) ->
						case gen_tcp:connect(CIP, CPort, [binary, {packet, 0}, {active, once}], 10) of
							{ok, Sock} ->
								gen_tcp:close(Sock),
								[{Node, {CIP, CPort}} | AL];
							{error, _} -> 
								AL
						end
				end,
			ActConns = lists:foldr(F, [], ConnNodes),
			erlang:start_timer(300000, self(), {check_conn_nodes, ConnNodes}),
			{ok, #state{active_conn_nodes = ActConns}}
	end.

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
handle_call({remove_conn_node, Node}, _From, #state{active_conn_nodes=ActiveConnNodes,  node_index=NodeIndex} = State) ->
	NewConnNodes = lists:keydelete(Node, 1, ActiveConnNodes),
	%% update index
	NewIndex = case length(ActiveConnNodes) < NodeIndex of
				   true -> 1;
				   false -> NodeIndex
			   end,	
	NewState = State#state{active_conn_nodes=NewConnNodes, node_index=NewIndex},
	{reply, ok, NewState};

handle_call(lookup_conn_node, _From, #state{active_conn_nodes=ActiveConnNodes, node_index=NodeIndex} = State) ->
	{_, ListenAddr} = lists:nth(NodeIndex, ActiveConnNodes),
	NewIndex = case length(ActiveConnNodes) > NodeIndex of
				   true -> NodeIndex + 1;
				   false -> 1
			   end,
	NewState = State#state{node_index=NewIndex},
	{reply, {ok, ListenAddr}, NewState};

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
handle_cast(_Msg, State) ->
	{noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_info({timeout, TimerRef, {check_conn_nodes, ConnNodes}}, #state{node_index=Index}) ->
	erlang:cancel_timer(TimerRef),
	F = fun({{CIP, CPort}, Node}, AL) ->
				case gen_tcp:connect(CIP, CPort, [binary, {packet, 0}, {active, once}], 10) of
					{ok, Sock} ->
						gen_tcp:close(Sock),
						[{Node, {CIP, CPort}} | AL];
					{error, _} -> 
						AL
				end
		end,
	ActConns = lists:foldl(F, [], ConnNodes),
	NewIndex = case Index > length(ActConns) of
				   true -> 1;
				   false -> Index
			   end,
	erlang:start_timer(300000, self(), {check_conn_nodes, ConnNodes}),
	{noreply, #state{active_conn_nodes=ActConns, node_index=NewIndex}};

handle_info(_Info, State) ->
	{noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, _State) -> %% called by gen_server when it's down(crash also)
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
	LbNodes = emobile_config:get_option(emlb_nodes),
	CtlBackNodes = emobile_config:get_option(emctl_back_nodes),	
	
	case length(CtlBackNodes) of
		0 -> 
			?CRITICAL_MSG("Start conn node[~p] failed: you should config at least ONE "
						  "control backup node, please check \"emobile.cfg\"! ~n", [node()]),
			exit(invalid_config);
		_ ->
			case lists:keyfind(node(), 2, LbNodes) of
				false ->
					?CRITICAL_MSG("Start load balance node[~p] failed: node name is not in the "
								  "configuration lb node list, please "
								  "check \"emobile.cfg\"! ~n", [node()]),
					exit(invalide_node_name);
				{{Ip, Port}, _} -> {ok, {Ip, Port}}
			end
	end.

loop([Socket, LastMsg])  ->
	receive
		{tcp, Socket, Bin} ->
			{ok, LastMsg1} = process_received_msg(Socket, <<LastMsg/binary, Bin/binary>>),
			inet:setopts(Socket, [{active, once}]),
			erlang:garbage_collect(self()),
			loop([Socket, LastMsg1]);	
		
		{close_conn, _Reason} ->
			gen_tcp:close(Socket),
			erlang:garbage_collect(self());
		
		{tcp_closed, Socket} ->
			?INFO_MSG("Mobile client[~p] disconnected.. ~n", [get(mobile_id)]),
			erlang:garbage_collect(self());
		
		{tcp_send, SendBin} ->
			case gen_tcp:send(Socket, SendBin) of
				ok ->
					erlang:garbage_collect(self()),
					loop([Socket, LastMsg]);
				
				{error, Reason} ->
					?ERROR_MSG("Ping client[~p] failed: ~p, close connection. ~n", [get(mobile_id), Reason]),
					erlang:garbage_collect(self())
			end;	
		
		Other ->
			?ERROR_MSG("Mobile connection process receive unkown message: ~p, ignore it. ~n", [Other]),
			loop([Socket, LastMsg])
	end.

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
					self() ! {close_conn, "receive invalid message length"},
					{error, <<>>}
			end;
		
		<<_SomeBin/binary>> ->
			{ok, Bin}
	end.

on_receive_msg(_MsgSize, MsgType, _MsgBody) ->
	case MsgType of
		?MSG_LOOKUP_SERVER -> on_lookup_server();
		Other -> ?ERROR_MSG("Receive unkown message type from client: ~p ~n", [Other]),
				 {error, "unkown message"}
	end.

on_lookup_server() ->
	{ok, {Ip, Port}} = gen_server:call(?MODULE, lookup_conn_node),
	{ok, {AA, BB, CC, DD}} = inet:getaddr(Ip, inet),
	MsgBin = <<10:2/?NET_ENDIAN-unit:8, 
               ?MSG_SERVER_ADDR: 2/?NET_ENDIAN-unit:8,
               AA: 1/unit:8,
               BB: 1/unit:8, 
               CC: 1/unit:8,
               DD: 1/unit:8,
               Port: 2/?NET_ENDIAN-unit:8>>,
    self() ! {tcp_send, MsgBin},
    self() ! {close_conn, "all done"},
    ok.

            
