%-----------------------------------------------------------------------------%
% Copyright (C) 2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

:- module dense_bitset.

:- interface.

:- import_module array, int.

:- type dense_bitset.

:- func init = dense_bitset.
:- mode (init = array_uo) is det.

:- pred member(int, dense_bitset).
:- mode member(in, array_ui) is semidet.

:- func insert(dense_bitset, int) = dense_bitset.
:- mode (insert(array_di, in) = array_uo) is det.

:- func delete(dense_bitset, int) = dense_bitset.
:- mode (delete(array_di, in) = array_uo) is det.

:- func union(dense_bitset, dense_bitset) = dense_bitset.
:- mode (union(array_di, array_di) = array_uo) is det.

%:- func intersection(dense_bitset, dense_bitset) = dense_bitset.
%:- mode (intersection(array_di, array_di) = array_uo) is det.

%:- func difference(dense_bitset, dense_bitset) = dense_bitset.
%:- mode (difference(array_di, array_di) = array_uo) is det.

:- pred foldl(pred(int, T, T), dense_bitset, T, T).
:- mode foldl(pred(in, in, out) is det, array_ui, in, out) is det.
:- mode foldl(pred(in, di, uo) is det, array_ui, di, uo) is det.
:- mode foldl(pred(in, array_di, array_uo) is det, array_ui,
		array_di, array_uo) is det.

:- implementation.

:- import_module list, require.

:- type dense_bitset == array(int).

init = array([0]).

member(I, A) :-
	max(A, Max),
	( word(I) >= 0, word(I) =< Max ->
		lookup(A, word(I), Word),
		bit(I) /\ Word \= 0
	;
		fail
	).

insert(A0, I) = A :-
	max(A0, Max),
	( word(I) > Max ->
		resize(A0, (Max + 1) * 2, 0, A1),
		A = insert(A1, I)
	; I >= 0 ->
		lookup(A0, word(I), Word0),
		Word = Word0 \/ bit(I),
		set(A0, word(I), Word, A)
	;
		error("insert: cannot use indexes < 0")
	).

delete(A0, I) = A :-
	max(A0, Max),
	( I > Max ->
		A = A0
	; I >= 0 ->
		lookup(A0, word(I), Word0),
		Word = Word0 /\ \ bit(I),
		set(A0, word(I), Word, A)
	;
		error("insert: cannot use indexes < 0")
	).

union(A, B) = C :-
	foldl((pred(I::in, C0::array_di, C1::array_uo) is det :-
		C1 = insert(C0, I)
	), A, B, C).

foldl(P, A0, Acc0, Acc) :-
	max(A0, Max),
	foldl1(0, Max, P, A0, Acc0, Acc).

:- pred foldl1(int, int, pred(int, T, T), dense_bitset, T, T).
:- mode foldl1(in, in, pred(in, in, out) is det, array_ui, in, out) is det.
:- mode foldl1(in, in, pred(in, di, uo) is det, array_ui, di, uo) is det.
:- mode foldl1(in, in, pred(in, array_di, array_uo) is det, array_ui,
		array_di, array_uo) is det.

foldl1(Min, Max, P, A0, Acc0, Acc) :-
	( Min =< Max ->
		foldl2(0, Min, P, A0, Acc0, Acc1),
		foldl1(Min + 1, Max, P, A0, Acc1, Acc)
	;
		Acc = Acc0
	).

:- pred foldl2(int, int, pred(int, T, T), dense_bitset, T, T).
:- mode foldl2(in, in, pred(in, in, out) is det, array_ui, in, out) is det.
:- mode foldl2(in, in, pred(in, di, uo) is det, array_ui, di, uo) is det.
:- mode foldl2(in, in, pred(in, array_di, array_uo) is det, array_ui,
		array_di, array_uo) is det.

foldl2(B, W, P, A0, Acc0, Acc) :-
	( B =< 31 ->
		lookup(A0, W, Word),
		( (1 << B) /\ Word \= 0 ->
			I = B + W * 32,
			call(P, I, Acc0, Acc1)
		;
			Acc1 = Acc0
		),
		foldl2(B + 1, W, P, A0, Acc1, Acc)
	;
		Acc = Acc0
	).

:- func word(int) = int.
word(I) = I // 32.

:- func bit(int) = int.
bit(I) = (1 << (I /\ 31)).

