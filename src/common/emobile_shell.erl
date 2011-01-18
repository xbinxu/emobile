%% Author: xuxb
%% Created: 2011-1-15
%% Description: help shell command get system configuration

-module(emobile_shell).

%%
%% Include files
%%

%%
%% Exported Functions
%%
-export([print_ctl_nodes/1, 
		 print_ctl_back_nodes/1,
		 print_conn_nodes/1,
		 print_push_nodes/1]).

%%
%% API Functions
%%

print_ctl_nodes(HostName) ->
	application:start(mnesia),
	emobile_config:start(),
	CtlNodes = emobile_config:get_option(emctl_nodes),
	
	F = fun({_, _, Node}) ->
				[NodeName, NodeHostName] = string:tokens(atom_to_list(Node), "@"),
				case NodeHostName =:= HostName of 
					true ->
						io:format("~p ", [list_to_atom(NodeName)]);
					false -> 
						void
				end
		end,
	lists:foreach(F, CtlNodes).


print_ctl_back_nodes(HostName) ->
	application:start(mnesia),
	emobile_config:start(),
	CtlNodes = emobile_config:get_option(emctl_back_nodes),
	
	F = fun(Node) ->
				[NodeName, NodeHostName] = string:tokens(atom_to_list(Node), "@"),
				case NodeHostName =:= HostName of 
					true ->
						io:format("~p ", [list_to_atom(NodeName)]);
					false -> 
						void
				end
		end,
	lists:foreach(F, CtlNodes).


print_conn_nodes(HostName) ->
	application:start(mnesia),
	emobile_config:start(),
	CtlNodes = emobile_config:get_option(emconn_nodes),
	
	F = fun({_, Node}) ->
				[NodeName, NodeHostName] = string:tokens(atom_to_list(Node), "@"),
				case NodeHostName =:= HostName of 
					true ->
						io:format("~p ", [list_to_atom(NodeName)]);
					false -> 
						void
				end
		end,
	lists:foreach(F, CtlNodes).


print_push_nodes(HostName) ->
	application:start(mnesia),
	emobile_config:start(),
	CtlNodes = emobile_config:get_option(empush_nodes),
	
	F = fun({_, Node}) ->
				[NodeName, NodeHostName] = string:tokens(atom_to_list(Node), "@"),
				case NodeHostName =:= HostName of 
					true ->
						io:format("~p ", [list_to_atom(NodeName)]);
					false -> 
						void
				end
		end,
	lists:foreach(F, CtlNodes).






%%
%% Local Functions
%%

