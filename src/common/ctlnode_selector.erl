%% Author: xuxb
%% Created: 2011-1-3
%% Description: TODO: Add description to lookup_ctl_node
-module(ctlnode_selector).

%%
%% Include files
%%

-include("loglevel.hrl").
-include_lib("stdlib/include/qlc.hrl").

%%
%% Exported Functions
%%

-export([init/0, get_ctl_node/1, get_ctl_back_node/1, test/0]).

%%
%% API Functions
%%

init() ->
	ets:new(emctl_nodes, [named_table]),
	ets:new(emctl_back_nodes, [named_table]),
	
	CtlNodes = emobile_config:get_option(emctl_nodes),
	
	F = fun({MobileId_s, MobileId_e, _}, Step) ->
				case Step of
					0 -> MobileId_e - MobileId_s + 1;
					_ -> case MobileId_e - MobileId_s + 1 of
							 Step -> Step;
							 _ -> exit(invalide_emctl_nodes_configure)
						 end
				end
		end,
	
	%% check and get step
	S = lists:foldl(F, 0, CtlNodes),
	emobile_config:add_option(ctl_mobile_id_step, S),
	lists:foreach(fun({MobileId_s, _, CtlNode}) -> ets:insert(emctl_nodes, {MobileId_s, CtlNode}) end, CtlNodes),
	
	CtlBackNodes = emobile_config:get_option(emctl_back_nodes),
	lists:foldl(fun(BackNode, Id) -> ets:insert(emctl_back_nodes, {Id, BackNode}), Id+1 end, 1, CtlBackNodes),
    ok.
	
get_ctl_node(MobileId) when is_integer(MobileId) ->
	Step = case get(ctl_mobile_id_step) of 
			   undefined ->
				   S = emobile_config:get_option(ctl_mobile_id_step),
				   put(ctl_mobile_id_step, S),
				   S;
			   Val -> Val
		   end,
	
	MobileId_s = (MobileId div Step) * Step  + 1,
	
	case ets:lookup(emctl_nodes, MobileId_s) of
		[{MobileId_s, Node}] -> Node;
		[] ->
			?CRITICAL_MSG("Can't find control node for mobile ~p, please add config! ~n", [MobileId]),
			undefined
	end.

get_ctl_back_node(MobileId) -> 
	Rem = case get(emctl_back_nodes_size) of
		undefined -> 
			N = ets:info(emctl_back_nodes, size),
			put(emctl_back_nodes_size, N),
			N;
		N -> N
	end,
	Id = (MobileId rem Rem) + 1,
	case ets:lookup(emctl_back_nodes, Id) of
		[{Id, Node}] ->
			Node;
		[] ->
			undefined
	end.


%%
%% Local Functions
%%

test() ->
	loglevel:set(5),
	application:start(mnesia, permanent),	
	emobile_config:start(),
	init(),
	get_ctl_node(155555).


