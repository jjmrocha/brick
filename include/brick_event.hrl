%%
%% Copyright 2016 Joaquim Rocha <jrocha@gmailbox.org>
%% 
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%

-record(brick_event, {name, value}).

-define(is_brick_event(Name, Event), (is_record(Event, brick_event) andalso Name =:= Event#brick_event.name)).

-define(BRICK_NEW_NODE_EVENT,'$brick_new_node').
-define(BRICK_NODE_DELETED_EVENT,'$brick_node_deleted').

-define(BRICK_NODE_UP_EVENT,'$brick_new_up').
-define(BRICK_NODE_DOWN_EVENT,'$brick_node_down').

-define(BRICK_CLUSTER_CHANGED_EVENT,'$brick_cluster_changed').
-define(BRICK_STATE_CHANGED_EVENT,'$brick_state_changed').
