%% $Id$

{application, emctl,
 [ {description, "Erlang Mobile Control Server"},
   {vsn, "0.1.0"},
   {modules, [db_ext, 
              dynamic_compile, 
              emobile_config, 
              loglevel, 
              socket_server, 
              ctlnode_selector, 
              emctl_app,
              emctl_sup,
              service_lookup_mobile_node,
              service_offline_msg
              ]},
   {mod, {emctl_app, []}}
 ]}.