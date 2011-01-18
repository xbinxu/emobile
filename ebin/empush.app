%% $Id$

{application, empush,
 [ {description, "Erlang Mobile Push Server"},
   {vsn, "0.1.0"},
   {modules, [db_ext, 
              dynamic_compile, 
              emobile_config, 
              loglevel, 
              socket_server, 
              ctlnode_selector, 
              empush_app,
              empush_sup,
              service_push_msg
              ]},   
   {mod, {empush_app, []}}
 ]}.