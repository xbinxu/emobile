%%% -------------------------------------------------------------------
%%% Author  : xuxb 
%%% Description : use this module serve "broadcast" request.
%%%               there must be only one "broadcast" task running at the same time.
%%%
%%% Created : 2011-1-12
%%% -------------------------------------------------------------------

-module(service_broadcast).

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

-include("loglevel.hrl").

%% --------------------------------------------------------------------
%% External exports
-export([start_link/0, broadcast_online/3, broadcast_all/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {}).

%% ====================================================================
%% External functions
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
			?CRITICAL_MSG("Start message broadcast service failed: ~p ~n", [Result]),
			Result
	end.

%% --------------------------------------------------------------------
%% Function: broadcast_online
%% Description: start message push tcp interface server(called from supervisor)
%% Returns: {ok, Pid} -> ok
%%          _         -> error
%% --------------------------------------------------------------------
broadcast_online(ServerId, TimeStampBin, Txt) ->
	spawn(fun() -> gen_server:call(?MODULE, 
								   {broadcast_online, ServerId, TimeStampBin, Txt}, 
								   infinity) 
		  end),
	ok.

%% --------------------------------------------------------------------
%% Function: broadcast_all
%% Description: start message push tcp interface server(called from supervisor)
%% Returns: {ok, Pid} -> ok
%%          _         -> error
%% --------------------------------------------------------------------
broadcast_all(ServerId, TimeStampBin, Txt) ->
	spawn(fun() -> gen_server:call(?MODULE, 
								   {broadcast_all, ServerId, TimeStampBin, Txt}, 
								   infinity) 
		  end),
	ok.



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
handle_call({broadcast_online, ServerId, TimeStampBin, MsgBin}, _From, State) ->
	ConnNodes1 = emobile_config:get_option(emconn_nodes),
	ConnNodes = lists:map(fun({_, ConnNode}) -> ConnNode end, ConnNodes1),
	
	%% wait until all nodes broadcast finished
	rpc:multicall(ConnNodes, 
				  service_mobile_conn, 
				  broadcast_online, 
				  [ServerId, TimeStampBin, MsgBin], 
				  infinity),	
	{reply, ok, State};

handle_call({broadcast_all, ServerId, TimeStampBin, MsgBin}, _From, State) ->
	CtlNodes1 = emobile_config:get_option(emctl_nodes),
	CtlNodes = lists:map(fun({_, _, CtlNode}) -> CtlNode end, CtlNodes1),
	
	%% wait until all nodes broadcast finished
	case rpc:multicall(CtlNodes, 
				  service_lookup_mobile_node, 
				  broadcast_all, 
				  [ServerId, TimeStampBin, MsgBin], 
				  infinity) of
		{_ResL, []} -> ok;
		{_ResL, BadNodes} ->
			erlang:start_timer(59999, self(), {broadcast_all, ServerId, TimeStampBin, MsgBin, BadNodes})
	end,
	{reply, ok, State};

handle_call(_Request, _From, State) ->
	{reply, ok, State}.

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
handle_info({timeout, _, {broadcast_all, ServerId, TimeStampBin, MsgBin, Nodes}}, State) ->
	case rpc:multicall(Nodes, 
				  service_lookup_mobile_node, 
				  broadcast_all, 
				  [ServerId, TimeStampBin, MsgBin], 
				  infinity) of
		{_ResL, []} -> ok;
		{_ResL, BadNodes} ->
			erlang:start_timer(59999, self(), {broadcast_all, ServerId, TimeStampBin, MsgBin, BadNodes})
	end,	
	{noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, _State) ->
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

