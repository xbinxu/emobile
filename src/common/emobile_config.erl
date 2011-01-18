%%% Author: xuxb
%%% Created: 2010-4-28
%%% Description: configuration reader
%%% Copyright (c) 2010 www.nd.com.cn

-module(emobile_config).

%%
%% Include files
%%

-include("loglevel.hrl").
-include_lib("kernel/include/file.hrl").

%%
%% Exported Functions
%%

-export([start/0, add_option/2, get_option/1]).

%%
%% API Functions
%%

-record(emobile_config, {key, value}).

%% @doc, start configuration reading and setting.
%% @spec () -> ok.
%%
start() ->
    mnesia:create_table(emobile_config,
			[{ram_copies, [node()]},
			 {attributes, record_info(fields, emobile_config)}]),	
    Config = get_emobile_config_path(),
    load_file(Config),
	ok.


%%
%% Local Functions
%%

%% @doc Get the filename of the emmogs configuration file.
%% The filename can be specified with: erl -config "/path/to/emmogs.cfg".
%% It can also be specified with the environtment variable emobile_config_PATH.
%% If not specified, the default value 'emmogs.cfg' is assumed.
%% @spec () -> string()
get_emobile_config_path() ->
	case application:get_env(config) of
		{ok, Path} -> Path;
		undefined ->
			case os:getenv("EMOBILE_CONFIG_PATH") of
				false ->
					"emobile.cfg";
				Path ->
					Path
			end
	end.

%% @doc Load the emmogs configuration file.
%% It also includes additional configuration files and replaces macros.
%% This function will crash if finds some error in the configuration file.
%% @spec (File::string()) -> ok
load_file(File) ->
    Terms = get_plain_terms_file(File),
    Terms_macros = replace_macros(Terms),
    lists:foreach(fun process_term/1,  Terms_macros).

%% @doc Read an emmogs configuration file and return the terms.
%% Input is an absolute or relative path to an emmogs config file.
%% Returns a list of plain terms,
%% in which the options 'include_config_file' were parsed
%% and the terms in those files were included.
%% @spec(string()) -> [term()]
get_plain_terms_file(File1) ->
    File = get_absolute_path(File1),
    case file:consult(File) of
	{ok, Terms} ->
	    include_config_files(Terms);
	{error, {LineNumber, erl_parse, _ParseMessage} = Reason} ->
	    ExitText = describe_config_problem(File, Reason, LineNumber),
	    ?ERROR_MSG(ExitText, []),
	    exit_or_halt(ExitText);
	{error, Reason} ->
	    ExitText = describe_config_problem(File, Reason),
	    ?ERROR_MSG(ExitText, []),
	    exit_or_halt(ExitText)
    end.

%% @doc Convert configuration filename to absolute path.
%% Input is an absolute or relative path to an emmogs configuration file.
%% And returns an absolute path to the configuration file.
%% @spec (string()) -> string()
get_absolute_path(File) ->
    case filename:pathtype(File) of
	absolute ->
	    File;
	relative ->
	    Config_path = get_emobile_config_path(),
	    Config_dir = filename:dirname(Config_path),
	    filename:absname_join(Config_dir, File)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Errors reading the config file

describe_config_problem(Filename, Reason) ->
    Text1 = lists:flatten("Problem loading emmogs config file " ++ Filename),
    Text2 = lists:flatten(" : " ++ file:format_error(Reason)),
    ExitText = Text1 ++ Text2,
    ExitText.

describe_config_problem(Filename, Reason, LineNumber) ->
    Text1 = lists:flatten("Problem loading emmogs config file " ++ Filename),
    Text2 = lists:flatten(" approximately in the line "
			  ++ file:format_error(Reason)),
    ExitText = Text1 ++ Text2,
    Lines = get_config_lines(Filename, LineNumber, 10, 3),
    ?ERROR_MSG("The following lines from your configuration file might be"
	       " relevant to the error: ~n~s", [Lines]),
    ExitText.

get_config_lines(Filename, TargetNumber, PreContext, PostContext) ->
    {ok, Fd} = file:open(Filename, [read]),
    LNumbers = lists:seq(TargetNumber-PreContext, TargetNumber+PostContext),
    NextL = io:get_line(Fd, no_prompt),
    R = get_config_lines2(Fd, NextL, 1, LNumbers, []),
    file:close(Fd),
    R.

get_config_lines2(_Fd, eof, _CurrLine, _LNumbers, R) ->
    lists:reverse(R);
get_config_lines2(_Fd, _NewLine, _CurrLine, [], R) ->
    lists:reverse(R);
get_config_lines2(Fd, Data, CurrLine, [NextWanted | LNumbers], R) when is_list(Data) ->
    NextL = io:get_line(Fd, no_prompt),
    if
	CurrLine >= NextWanted ->
	    Line2 = [integer_to_list(CurrLine), ": " | Data],
	    get_config_lines2(Fd, NextL, CurrLine+1, LNumbers, [Line2 | R]);
	true ->
	    get_config_lines2(Fd, NextL, CurrLine+1, [NextWanted | LNumbers], R)
    end.

%% If emmogs isn't yet running in this node, then halt the node
exit_or_halt(ExitText) ->
    case [Vsn || {emmogs, _Desc, Vsn} <- application:which_applications()] of
	[] ->
	    timer:sleep(1000),
	    halt(ExitText);
	[_] ->
	    exit(ExitText)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Support for 'include_config_file'

%% @doc Include additional configuration files in the list of terms.
%% @spec ([term()]) -> [term()]
include_config_files(Terms) ->
    include_config_files(Terms, []).

include_config_files([], Res) ->
    Res;
include_config_files([{include_config_file, Filename} | Terms], Res) ->
    include_config_files([{include_config_file, Filename, []} | Terms], Res);
include_config_files([{include_config_file, Filename, Options} | Terms], Res) ->
    Included_terms = get_plain_terms_file(Filename),
    Disallow = proplists:get_value(disallow, Options, []),
    Included_terms2 = delete_disallowed(Disallow, Included_terms),
    Allow_only = proplists:get_value(allow_only, Options, all),
    Included_terms3 = keep_only_allowed(Allow_only, Included_terms2),
    include_config_files(Terms, Res ++ Included_terms3);
include_config_files([Term | Terms], Res) ->
    include_config_files(Terms, Res ++ [Term]).

%% @doc Filter from the list of terms the disallowed.
%% Returns a sublist of Terms without the ones which first element is
%% included in Disallowed.
%% @spec (Disallowed::[atom()], Terms::[term()]) -> [term()]
delete_disallowed(Disallowed, Terms) ->
    lists:foldl(
      fun(Dis, Ldis) ->
	      delete_disallowed2(Dis, Ldis)
      end,
      Terms,
      Disallowed).

delete_disallowed2(Disallowed, [H|T]) ->
    case element(1, H) of
	Disallowed ->
	    ?WARNING_MSG("The option '~p' is disallowed, "
			 "and will not be accepted", [Disallowed]),
	    delete_disallowed2(Disallowed, T);
	_ ->
	    [H|delete_disallowed2(Disallowed, T)]
    end;
delete_disallowed2(_, []) ->
    [].

%% @doc Keep from the list only the allowed terms.
%% Returns a sublist of Terms with only the ones which first element is
%% included in Allowed.
%% @spec (Allowed::[atom()], Terms::[term()]) -> [term()]
keep_only_allowed(all, Terms) ->
    Terms;
keep_only_allowed(Allowed, Terms) ->
    {As, NAs} = lists:partition(
		  fun(Term) ->
			  lists:member(element(1, Term), Allowed)
		  end,
		  Terms),
    [?WARNING_MSG("This option is not allowed, "
		  "and will not be accepted:~n~p", [NA])
     || NA <- NAs],
    As.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Support for Macro

%% @doc Replace the macros with their defined values.
%% @spec (Terms::[term()]) -> [term()]
replace_macros(Terms) ->
    {TermsOthers, Macros} = split_terms_macros(Terms),
    replace(TermsOthers, Macros).

%% @doc Split Terms into normal terms and macro definitions.
%% @spec (Terms) -> {Terms, Macros}
%%       Terms = [term()]
%%       Macros = [macro()]
split_terms_macros(Terms) ->
    lists:foldl(
      fun(Term, {TOs, Ms}) ->
	      case Term of
		  {define_macro, Key, Value} -> 
		      case is_atom(Key) and is_all_uppercase(Key) of
			  true -> 
			      {TOs, Ms++[{Key, Value}]};
			  false -> 
			      exit({macro_not_properly_defined, Term})
		      end;
		  Term ->
		      {TOs ++ [Term], Ms}
	      end
      end,
      {[], []},
      Terms).

%% @doc Recursively replace in Terms macro usages with the defined value.
%% @spec (Terms, Macros) -> Terms
%%       Terms = [term()]
%%       Macros = [macro()]
replace([], _) ->
    [];
replace([Term|Terms], Macros) ->
    [replace_term(Term, Macros) | replace(Terms, Macros)].

replace_term(Key, Macros) when is_atom(Key) ->
    case is_all_uppercase(Key) of
	true ->
	    case proplists:get_value(Key, Macros) of
		undefined -> exit({undefined_macro, Key});
		Value -> Value
	    end;
	false ->
	    Key
    end;
replace_term({use_macro, Key, Value}, Macros) ->
    proplists:get_value(Key, Macros, Value);
replace_term(Term, Macros) when is_list(Term) ->
    replace(Term, Macros);
replace_term(Term, Macros) when is_tuple(Term) ->
    List = tuple_to_list(Term),
    List2 = replace(List, Macros),
    list_to_tuple(List2);
replace_term(Term, _) ->
    Term.

is_all_uppercase(Atom) ->
    String = erlang:atom_to_list(Atom),
    lists:all(fun(C) when C >= $a, C =< $z -> false;
		 (_) -> true
	      end, String).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Process terms

process_term(Term) ->
	case Term of		
		{loglevel, Loglevel} ->
			loglevel:set(Loglevel);
		
		{Key, Value} ->
			add_option(Key, Value);
		
		Unallowed ->
			?WARNING_MSG("Emmogs find an unallowed term: ~p when processing config file.~n", [Unallowed])
	end.


add_option(Opt, Val) ->
	case mnesia:transaction(fun() -> mnesia:write(#emobile_config{key = Opt, value = Val}) end) of
		{atomic, _} -> ok;
		{aborted, {no_exists, Table}} ->
			MnesiaDirectory = mnesia:system_info(directory),
			?ERROR_MSG("Error reading Mnesia database spool files:~n"
					   "The Mnesia database couldn't read the spool file for the table '~p'.~n"
				       "emmogs needs read and write access in the directory:~n   ~s~n"
					   "Maybe the problem is a change in the computer hostname,~n"
					   "or a change in the Erlang node name, which is currently:~n   ~p~n"
					   "Check the ejabberd guide for details about changing the~n"
					   "computer hostname or Erlang node name.~n",
					   [Table, MnesiaDirectory, node()]),
			exit("Error reading Mnesia database")
	end.


get_option(Opt) ->
    case ets:lookup(emobile_config, Opt) of
	[#emobile_config{value = Val}] ->
	    Val;
	_ ->
	    undefined
    end.

%% @spec (Path::string()) -> true | false
%% is_file_readable(Path) ->
%%     case file:read_file_info(Path) of
%% 	{ok, FileInfo} ->
%% 	    case {FileInfo#file_info.type, FileInfo#file_info.access} of
%% 		{regular, read} -> true;
%% 		{regular, read_write} -> true;
%% 		_ -> false
%% 	    end;
%% 	{error, _Reason} ->
%% 	    false
%%     end.

