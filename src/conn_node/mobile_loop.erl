%% Author: Administrator
%% Created: 2011-1-17
%% Description: TODO: Add description to mobile_loop
-module(mobile_loop).

%%
%% Include files
%%

-include("loglevel.hrl").

%%
%% Exported Functions
%%
-export([loop/1]).

%%
%% API Functions
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
loop([Socket, LastMsg]) ->
	receive
		{tcp, Socket, Bin} ->
%% 			?INFO_MSG("LastMsg: ~p, merged bin: ~p ~n", [LastMsg, <<LastMsg/binary, Bin/binary>>]),
			{ok, LastMsg1} = mobile_network:process_received_msg(Socket, <<LastMsg/binary, Bin/binary>>),
			inet:setopts(Socket, [{active, once}]),
			erlang:garbage_collect(self()),
			loop([Socket, LastMsg1]);			
		
		{tcp_closed, Socket} ->
			?INFO_MSG("Mobile client[~p] disconnected.. ~n", [get(mobile_id)]),
			erlang:garbage_collect(self());
		
		{kick_out, Reason} ->
			?ERROR_MSG("Mobile[~p] is kicked out of reason: ~p. ~n", [get(mobile_id), Reason]),
			erlang:garbage_collect(self());
		
		{close_conn, Reason} ->
			?ERROR_MSG("Mobile client is closed by reason: ~p. ~n", [Reason]),
			erlang:garbage_collect(self());
		
		{tcp_send, CtlNode, SendBin} ->
			case mobile_network:tcp_send(CtlNode, Socket, SendBin) of
				ok -> loop([Socket, LastMsg]);
				{error, Reason} ->
					?ERROR_MSG("Send tcp data to mobile client failed: ~p. ~n", [Reason]),
					erlang:garbage_collect(self())
			end;
		
		{tcp_send_ping, SendBin} ->
			case gen_tcp:send(Socket, SendBin) of
				ok ->
					erlang:garbage_collect(self()),
					loop([Socket, LastMsg]);
				
				{error, Reason} ->
					?ERROR_MSG("Ping client[~p] failed: ~p, close connection. ~n", [get(mobile_id), Reason]),
					erlang:garbage_collect(self())
			end;	
		
		{timeout, _TimerRef, login_timer} -> %% stop process if client doesn't login in time
			case get(mobile_id) of 
				undefined ->
					?ERROR_MSG("Client connection does not login in 30 seconds. ~n", []),
					erlang:garbage_collect(self());
				_ ->
					erlang:garbage_collect(self()),
					loop([Socket, LastMsg])
			end;
		
		Other ->
			?ERROR_MSG("Mobile connection process receive unkown message: ~p, ignore it. ~n", [Other]),
			loop([Socket, LastMsg])
	end.


%%
%% Local Functions
%%

