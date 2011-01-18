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
			?INFO_MSG("Receive binary: ~p ~n", [Bin]),
			{ok, LastMsg1} = admin_network:process_received_msg(Socket, <<LastMsg/binary, Bin/binary>>),
			inet:setopts(Socket, [{active, once}]),
			erlang:garbage_collect(self()),
			loop([Socket, LastMsg1]);			
		
		{tcp_closed, Socket} ->
			erlang:garbage_collect(self());
	
		{tcp_send, SendBin} ->
			case gen_tcp:send(Socket, SendBin) of
				ok ->
					erlang:garbage_collect(self()),
					loop([Socket, LastMsg]);
				
				{error, Reason} ->
					?ERROR_MSG("Send tcp data to admin client failed: ~p. ~n", [Reason]),
					erlang:garbage_collect(self())
			end;

		Other ->
			?ERROR_MSG("Admin connection process receive unkown message: ~p, ignore it. ~n", [Other]),
			loop([Socket, LastMsg])
	end.


%%
%% Local Functions
%%

