:- module arbitrary_constraint_pred_2.
:- interface.

:- import_module float, io.
:- import_module list.

:- typeclass solver_for(B, S) where [
	func coerce(B) = S
].

:- instance solver_for(list(T), float) where [
	coerce(_) = 42.0
].

:- pred mg(T, T) <= solver_for(list(T), T).
:- mode mg(in, out) is det.

:- pred main(io::di, io::uo) is det.

:- implementation.
:- import_module std_util.

mg(S0, S) :-
	( semidet_succeed ->
		S = coerce([S0])
	;
		S = S0
	).


main -->
	{ mg(1.0, S) },
	io__print(S),
	io__nl.
