%-----------------------------------------------------------------------------%
% Copyright (C) 2000-2002,2004 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% module pa_datastruct: defines the datastruct type used within 
% 	possible alias analysis, and used during structure reuse analysis. 
% 	A datastruct essentially designates a selector path within
%	a program variable. 
% main author: nancy

% notes: 
% 1. contains some code which is common to Wim's BTA analysis. At some
%    point this should be really shared. It is not the case at this
%    moment. 
% 2. _partially instantiated datastructures_ : the day they'll be 
%    introduced, a couple of things will have to be changed.

:- module possible_alias__pa_datastruct.

:- interface.

:- import_module hlds__hlds_data.
:- import_module hlds__hlds_module.
:- import_module hlds__hlds_pred.
:- import_module parse_tree__prog_data.
:- import_module possible_alias__pa_selector.

:- import_module map, io, term.

%-------------------------------------------------------------------%
%-- exported types

:- type datastruct.

%-------------------------------------------------------------------%
%-- exported predicates

%-------------------------------------------------------------------%
% predicates for the datastruct type
%-------------------------------------------------------------------%
	% init(Var, D)
	% Create an initial top-datastruct for variable Var.
:- pred init(prog_var::in, datastruct::out) is det.
:- func init(prog_var) = datastruct. 

	% Initialise a datastructure by its variable and selector. 
:- pred init(prog_var::in, selector::in, datastruct::out) is det.

	% init(Var, Cons, Index, D)
	% Create an initial datastruct Var^(Cons,Index), thus a data structure
	% with a selector consisting of only one unit selector, namely the one
	% identified by the constructor and index within that constructor. 
:- pred init(prog_var::in, cons_id::in, int::in, datastruct::out) is det.

:- pred get_var(datastruct::in, prog_var::out) is det.
:- func var(datastruct) = prog_var. 

:- pred get_selector(datastruct::in, selector::out) is det.
:- func selector(datastruct) = selector. 

	% Extend the given datastructure with an additional path.
:- pred termshift(datastruct::in, selector::in, datastruct::out) is det. 

	% less_or_equal(LongerData,ShorterData,Selector)
	% Check whether by extending the ShorterData with some selector
	% Selector one can obtain LongerData. 
	% If the datastructs concern different variables, fail right away.
:- pred less_or_equal(module_info::in, proc_info::in, datastruct::in,
		datastruct::in, selector::out) is semidet.

	% Check whether the two given datastructs are related to the
	% same variable or not. 
:- pred same_vars(datastruct::in, datastruct::in) is semidet.

	% Check whether the given datastructs are identical or not.
:- pred equal(datastruct::in, datastruct::in) is semidet.

	% Rename the variable of the given datastruct.
:- pred rename(map(prog_var,prog_var)::in, datastruct::in, 
		datastruct::out) is det.

:- pred rename_types(term__substitution(tvar_type)::in, 
		datastruct::in, datastruct::out) is det. 

	% Printing routines
:- pred print(pred_info::in, proc_info::in, datastruct::in, 
		io__state::di, io__state::uo) is det.

:- pred to_user_declared(datastruct::in, prog_varset::in, 
		tvarset::in, string::out) is det. 

	% Parsing routines
:- pred parse_term(term(T)::in, datastruct::out) is det.

:- pred normalize_wti(module_info::in, proc_info::in, 
		datastruct::in, datastruct::out) is det.

:- pred apply_widening(module_info::in, proc_info::in, datastruct::in, 
			datastruct::out) is det.
:- func apply_widening(module_info, proc_info, datastruct) = datastruct.

:- func type_of_node(module_info, proc_info, datastruct) = (type). 
:- func type_of_node_with_vartypes(module_info, map(prog_var, type), 
						datastruct) = (type). 

%-------------------------------------------------------------------%
%-------------------------------------------------------------------%
:- implementation.

:- import_module check_hlds__type_util.

:- import_module string, varset, require, list.

:- type datastruct ---> cel(prog_var, pa_selector__selector).

get_var(cel(Var, _Sel), Var).
var(cel(Var, _Sel)) = Var. 
get_selector(cel(_Var, Sel), Sel).
selector(cel(_Var, Sel)) = Sel.


rename(MAP, DATAin, DATAout) :-
	DATAin = cel(VAR, SEL),
	map__lookup(MAP, VAR, RVAR),
	DATAout = cel(RVAR, SEL).

rename_types(Subst, Data0, Data) :- 
	Data0 = cel(Var, Sel0), 
	pa_selector__rename_types(Subst, Sel0, Sel), 
	Data = cel(Var, Sel). 

equal(D1, D2):- D1 = D2.

same_vars(D1, D2):-
	get_var(D1,V),
	get_var(D2,V).

less_or_equal(ModuleInfo, ProcInfo, D1,D2, EXT):-
	same_vars(D1,D2),
	get_var(D1,ProgVar), 
	proc_info_vartypes(ProcInfo, VarTypes), 
	map__lookup(VarTypes, ProgVar, ProgVarType), 
	(
		equal(D1,D2)
	->
		pa_selector__init(EXT)
	;
		get_selector(D1,S1),
		get_selector(D2,S2),
		pa_selector__less_or_equal(ModuleInfo,S1,S2,ProgVarType,EXT)
	).

termshift(Din, S, Dout):-
	Din = cel(V,Sin),
	pa_selector__termshift(Sin,S,Sout),
	Dout = cel(V,Sout).

init(V, CONS, INDEX, Dout) :-
	pa_selector__init(CONS,INDEX, SEL),
	Dout = cel(V,SEL).

init(V, Dout) :-
	SEL = [],
	Dout = cel(V, SEL).
init(V) = D :- init(V, D).

init(V, Sel, Dout) :- 
	Dout = cel(V, Sel). 

print(PredInfo, ProcInfo, D) --> 
	{ D = cel(ProgVar, SEL) },
	{ proc_info_varset(ProcInfo, ProgVarset) },
	{ varset__lookup_name(ProgVarset, ProgVar, ProgName) },
	io__write_string("cel("),
	io__write_string(ProgName), 
	io__write_string(", "),
	{ pred_info_typevarset(PredInfo, TypeVarSet) }, 
	pa_selector__print(SEL, TypeVarSet),
	io__write_string(")").

to_user_declared(Data, ProgVarSet, TypeVarSet, String):- 
	Data = cel(ProgVar, Selector), 
	varset__lookup_name(ProgVarSet, ProgVar, ProgName), 
	pa_selector__to_user_declared(Selector, TypeVarSet, 
			SelectorString), 
	string__append_list(["cel(", ProgName, ", ", SelectorString, ")"], 
		String). 

parse_term(TERM, Data) :- 
   (
      TERM = term__functor(term__atom(CONS), Args, _)
   ->
      (
         CONS = "cel"
      ->
         (
            Args = [ VarTerm, SelectorTerm ]
         ->
           (
              VarTerm = term__variable(VAR)
	   ->
	      term__coerce_var(VAR, PROGVAR),
	      pa_selector__parse_term(SelectorTerm, SELECTOR),
	      Data = cel(PROGVAR, SELECTOR)
	   ;
	      error("(pa_datastruct) parse_term: wrong term. variable, should be functor")
	   )
	 ;
	   list__length(Args, L),
	   string__int_to_string(L, LS),
	   string__append_list(["(pa_datastruct) parse_term: wrong number of arguments. cel/",LS,
	   			"should be cel/2"],Msg),
	   error(Msg)
	 )
      ;
         string__append_list(["(pa_datastruct) parse_term: wrong constructor. `",CONS,
	 			"' should be `cel'"],Msg),
	   error(Msg)
      )
   ;
      error("(pa_datastruct) parse_term: term not a functor")
   ).


normalize_wti(HLDS, ProcInfo, Din, Dout):-
	proc_info_vartypes(ProcInfo, VarTypes), 
	normalize_wti_2(HLDS, VarTypes, Din, Dout). 

	% normalize with type information
:- pred normalize_wti_2(module_info, vartypes, 
		datastruct, datastruct).
:- mode normalize_wti_2(in, in, in, out) is det.

normalize_wti_2(HLDS, VarTypes, D0, D):-
	D0 = cel(ProgVar, SEL0), 
	map__lookup(VarTypes, ProgVar, VarType),
	pa_selector__normalize_wti(HLDS, VarType, SEL0, SEL),
	D = cel(ProgVar, SEL).

apply_widening(ModuleInfo, ProcInfo, D0, D):- 
	D0 = cel(ProgVar, Sel0), 
	proc_info_vartypes(ProcInfo, VarTypes), 
	map__lookup(VarTypes, ProgVar, ProgVarType), 
	pa_selector__apply_widening(ModuleInfo, ProgVarType, Sel0, Sel), 
	D = cel(ProgVar, Sel). 

apply_widening(ModuleInfo, ProcInfo, D0) = D :- 
	apply_widening(ModuleInfo, ProcInfo, D0, D).

type_of_node(ModuleInfo, ProcInfo, Data) = Type :- 
	proc_info_vartypes(ProcInfo, VarTypes), 
	Type = type_of_node_with_vartypes(ModuleInfo, VarTypes, Data). 

type_of_node_with_vartypes(ModuleInfo, VarTypes, Data) = Type :- 
	Data = cel(ProgVar, Sel), 
	map__lookup(VarTypes, ProgVar, ProgVarType), 
	Type = pa_selector__type_of_node(ModuleInfo, ProgVarType, Sel). 

