%% Author: Administrator
%% Created: 2011-2-21
%% Description: TODO: Add description to emlb_app
-module(emlb_app).

-behaviour(application).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

%% --------------------------------------------------------------------
%% Behavioural exports
%% --------------------------------------------------------------------
-export([
	 start/2,
	 stop/1
        ]).

%% --------------------------------------------------------------------
%% Internal exports
%% --------------------------------------------------------------------
-export([]).

%% --------------------------------------------------------------------
%% Macros
%% --------------------------------------------------------------------

%% --------------------------------------------------------------------
%% Records
%% --------------------------------------------------------------------

%% --------------------------------------------------------------------
%% API Functions
%% --------------------------------------------------------------------


%% ====================================================================!
%% External functions
%% ====================================================================!
%% --------------------------------------------------------------------
%% Func: start/2
%% Returns: {ok, Pid}        |
%%          {ok, Pid, State} |
%%          {error, Reason}
%% --------------------------------------------------------------------
start(_Type, _StartArgs) ->
	case node() of
		'nonode@nohost' ->
			{error, "emlb must run in distributed eviroment."};
		Node ->
			NodeName = atom_to_list(Node),
			[NodePrefix, _] = string:tokens(NodeName, "@"),
			LogfileName = string:concat("error_log//", string:concat(NodePrefix, ".log")),
			error_logger:add_report_handler(ejabberd_logger_h, LogfileName),
			init_mnesia(),
			emobile_config:start(),
			ctlnode_selector:init(),
			case emlb_sup:start_link() of
				{ok, Pid} ->
					{ok, Pid};
				Error ->
					Error
			end
	end.
	


%% --------------------------------------------------------------------
%% Func: stop/1
%% Returns: any
%% --------------------------------------------------------------------
stop(_State) ->
    ok.

%% ====================================================================
%% Internal functions
%% ====================================================================
init_mnesia()->
	%% initialize database
	case mnesia:system_info(extra_db_nodes) of
		[] ->
			mnesia:create_schema([node()]);
		_ ->
			ok
	end,
	application:start(mnesia, permanent),
	mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity).
