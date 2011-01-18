%%% -------------------------------------------------------------------
%%% Author  : xuxb
%%% Description :
%%%
%%% Created : 2011-1-2
%%% -------------------------------------------------------------------
-module(service_offline_msg).

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

-include("loglevel.hrl").
-include("message_define.hrl").

%% --------------------------------------------------------------------
%% External exports
-export([start_link/0, save_undelivered_msg/2, send_offline_msgs/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {}).

-record(unique_ids, {type, id}).
-record(undelivered_msgs, {id = 0, mobile_id = 0, msg_bin = <<>>}).

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
			?CRITICAL_MSG("Start message push server service failed: ~p ~n", [Result]),
			Result
	end.

%% --------------------------------------------------------------------
%% Function: on_msg_send_failed/0
%% Description: save undelivered message to database
%% Returns: ok  -> success
%%          {error, Reason} -> failed
%% --------------------------------------------------------------------
save_undelivered_msg(TargetMobileId, MsgBin) ->
	Id = mnesia:dirty_update_counter(unique_ids, undelivered_msg, 1),
	Record = #undelivered_msgs{id = Id, mobile_id = TargetMobileId, msg_bin = MsgBin},
    case mnesia:transaction(fun() -> mnesia:write(Record) end) of
		{atomic, ok} ->
			ok;
		{aborted, Reason} ->
			?CRITICAL_MSG("Save undelivered message to database failed: ~p ~n", [Reason]),
			{error, "Database failed"}
	end.

%% --------------------------------------------------------------------
%% Function: send_offline_msgs/2
%% Description: save undelivered message to database
%% Returns: ok  -> success
%%          {error, Reason} -> failed
%% --------------------------------------------------------------------
send_offline_msgs(MobileId, ConnNode) ->
	case mnesia:dirty_index_read(undelivered_msgs, MobileId, #undelivered_msgs.mobile_id) of
		[] -> ok;
		List ->
			F = fun(#undelivered_msgs{id = Id, mobile_id = TargetMobileId, msg_bin = MsgBin}) ->
						case rpc:call(ConnNode, service_mobile_conn, send_message, [node(), TargetMobileId, MsgBin]) of
							ok -> 
								mnesia:dirty_delete(undelivered_msgs, Id);
							{error, Reason} ->
								?ERROR_MSG("Send offline message to mobile[~p] by conn node[~p] failed: ~p ~n", [MobileId, ConnNode, Reason]);
							{badrpc, Reason} -> 
								?ERROR_MSG("RPC call to node[~p] failed: ~p, reset this node. ~n", [ConnNode, Reason]),
								service_lookup_mobile_node:on_conn_node_down(ConnNode)
						end
				end,
			lists:foreach(F, lists:reverse(List))
	end.


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
	mnesia:create_table(undelivered_msgs,
						[{disc_copies, [node()]},
						 {attributes, record_info(fields, undelivered_msgs)},
						 {index, [mobile_id]}]),	
	
	mnesia:create_table(unique_ids, 
						[{disc_copies, [node()]},
						 {attributes, record_info(fields, unique_ids)}]),
	
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

