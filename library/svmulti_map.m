%-----------------------------------------------------------------------------%
% Copyright (C) 2005 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: svmulti_map.m.
% Author: dylan.
% Stability: low.
%
% This file provides an interface to the 'multi_map' ADT that is conducive to
% the use of state variable notation. The predicates here do the same thing as
% their counterparts in the multi_map module; the only difference is the order
% of the arguments.
%
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module svmulti_map.

:- interface.

:- import_module list.
:- import_module multi_map.

%-----------------------------------------------------------------------------%
	
	% Insert a new key and corresponding value into a multi_map.
	% Fail if the key already exists.
	%
:- pred svmulti_map__insert(K::in, V::in,
	multi_map(K, V)::in, multi_map(K, V)::out) is semidet.

	% Insert a new key and corresponding value into a multi_map.
	% Abort if the key already exists.
	%
:- pred svmulti_map__det_insert(K::in, V::in,
	multi_map(K, V)::in, multi_map(K, V)::out) is det.
	
	% Update (add) the value corresponding to a given key.
	% Fail if the key does not already exist.
	%
:- pred svmulti_map__update(K::in, V::in,
	multi_map(K, V)::in, multi_map(K, V)::out) is semidet.
	
	% Update (add) the value corresponding to a given key.
	% Abort if the key doesn't already exist.
	%
:- pred svmulti_map__det_update(K::in, V::in,
	multi_map(K, V)::in, multi_map(K, V)::out) is det.

	% Update (replace) the value corresponding to a given key.
	% Abort if the key does not already exist.
	%
:- pred svmulti_map__det_replace(K::in, list(V)::in,
	multi_map(K, V)::in, multi_map(K, V)::out) is det.
	
	% Update (add) value if the key is already present, otherwise
	% insert the new key and value.
	%
:- pred svmulti_map__set(K::in, V::in,
	multi_map(K, V)::in, multi_map(K, V)::out) is det.

:- pred svmulti_map__add(K::in, V::in,
	multi_map(K, V)::in, multi_map(K, V)::out) is det.

	% Delete a key and data from a multi_map
	% If the key is not present, leave the multi_map unchanged.
	%
:- pred svmulti_map__delete(K::in, multi_map(K, V)::in, multi_map(K, V)::out)
	is det.

	% Delete a data value from a key in a multi_map
	% If the key is not present, leave the multi_map unchanged.
	%
:- pred svmulti_map__delete(K::in, V::in,
	multi_map(K, V)::in, multi_map(K, V)::out) is det.

	% Delete a key-value pair from a multi_map and return the value.
	% Fail if the key is not present.
	%
:- pred svmulti_map__remove(K::in, list(V)::out,
	multi_map(K, V)::in, multi_map(K, V)::out) is semidet.

	% Delete a key-value pair from a multi_map and return the value.
	% Abort if the key is not present.
	%
:- pred svmulti_map__det_remove(K::in, list(V)::out,
	multi_map(K, V)::in, multi_map(K, V)::out) is det.

	% Remove the smallest item from the multi_map, fail if
	% the multi_map is empty.
	%
:- pred svmulti_map__remove_smallest(K::out, list(V)::out,
	multi_map(K, V)::in, multi_map(K, V)::out) is semidet.

%----------------------------------------------------------------------------%
%----------------------------------------------------------------------------%

:- implementation.

svmulti_map__insert(K, V, MultiMap0, MultiMap) :-
	multi_map__insert(MultiMap0, K, V, MultiMap). 	

svmulti_map__det_insert(K, V, MultiMap0, MultiMap) :-
	multi_map__det_insert(MultiMap0, K, V, MultiMap).

svmulti_map__update(K, V, MultiMap0, MultiMap) :-
	multi_map__update(MultiMap0, K, V, MultiMap).

svmulti_map__det_update(K, V, MultiMap0, MultiMap) :-
	multi_map__det_update(MultiMap0, K, V, MultiMap).

svmulti_map__det_replace(K, V, MultiMap0, MultiMap) :-
	multi_map__det_replace(MultiMap0, K, V, MultiMap).

svmulti_map__set(K, V, MultiMap0, MultiMap) :-
	multi_map__set(MultiMap0, K, V, MultiMap).

svmulti_map__add(K, V, MultiMap0, MultiMap) :-
	multi_map__add(MultiMap0, K, V, MultiMap).

svmulti_map__delete(K, MultiMap0, MultiMap) :-
	multi_map__delete(MultiMap0, K, MultiMap).

svmulti_map__delete(K, V, MultiMap0, MultiMap) :-
	multi_map__delete(MultiMap0, K, V, MultiMap).

svmulti_map__remove(K, V, MultiMap0, MultiMap) :-
	multi_map__remove(MultiMap0, K, V, MultiMap).

svmulti_map__det_remove(K, V, MultiMap0, MultiMap) :-
	multi_map__det_remove(MultiMap0, K, V, MultiMap).

svmulti_map__remove_smallest(K, V, MultiMap0, MultiMap) :-
	multi_map__remove_smallest(MultiMap0, K, V, MultiMap).

%----------------------------------------------------------------------------%
:- end_module svmulti_map.
%----------------------------------------------------------------------------%