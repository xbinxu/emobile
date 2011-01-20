%% Author: Administrator
%% Created: 2011-1-18
%% Description: TODO: Add description to admin_loop
-module(admin_loop).

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
			{ok, LastMsg1} = admin_network:process_received_msg(Socket, <<LastMsg/binary, Bin/binary>>),
			inet:setopts(Socket, [{active, once}]),
			erlang:garbage_collect(self()),
			loop([Socket, LastMsg1]);			
		
		{tcp_closed, Socket} ->
			?INFO_MSG("Server[~p] disconnected.. ~n", [get(server_id)]),
			erlang:garbage_collect(self());
		
		{kick_out, Reason} ->
			?ERROR_MSG("Server[~p] is kicked out of reason: ~p. ~n", [get(server_id), Reason]),
			erlang:garbage_collect(self());		
		
		{tcp_send, Pid, CtlNode, TimeStamp, SendBin} ->
			case self() of
				Pid -> void;
				_ -> Pid ! {tcp_send, ok}
			end,
			case admin_network:tcp_send(CtlNode, Socket, TimeStamp, SendBin) of
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

		Other ->
			?ERROR_MSG("Admin connection process receive unkown message: ~p, ignore it. ~n", [Other]),
			loop([Socket, LastMsg])
	end.


%%
%% Local Functions
%%

