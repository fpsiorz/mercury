<<<<<<< source_stats.awk
=======
#  Usage: awk -f source_stats.awk *.nl
#
#  This computes some simple statistics about Mercury source code.

>>>>>>> 1.2
{ lines++; }

/^[ 	]*$/		{ blank++; next; }
/^[ 	]*%[ 	%-]*$/	{ blank++; next; }
/^[ 	]*%/		{ comments++; next; }

/is[ 	]*det/		{ det_preds++; }
/is[ 	]*semidet/	{ semidet_preds++; }
/is[ 	]*nondet/	{ nondet_preds++; }

/^:-[ 	]*pred/		{ pred_count++; in_pred = 1; }
/^:-[ 	]*mode/		{ mode_count++; in_mode = 1; }
/^:-[ 	]*type/		{ type_count++; in_type = 1; }
/^:-[ 	]*inst/		{ inst_count++; in_inst = 1; }
/^:-/			{ in_decl = 1; }
{
	if (in_pred) preds++;
	if (in_mode) modes++;
	if (in_type) types++;
	if (in_inst) insts++;
	if (in_decl) decls++;
}
/\.[ 	]*$/	{ in_pred = in_mode = in_type = in_inst = in_decl = 0; }
END {
	printf("Number of types:                %6d\n", type_count);
	printf("Number of insts:                %6d\n", inst_count);
	printf("Number of predicates:           %6d\n", pred_count);
	printf("Number of modes:                %6d\n", mode_count);
	printf("        - det:                  %6d (%6.2f%%)\n",				det_preds, 100 * det_preds / mode_count);
	printf("        - semidet:              %6d (%6.2f%%)\n",				semidet_preds, 100 * semidet_preds / mode_count);
	printf("        - nondet:               %6d (%6.2f%%)\n",				nondet_preds, 100 * nondet_preds / mode_count);
	printf("Average modes per predicate:    %6.3f\n",					mode_count / pred_count);
	printf("\n");
	printf("Blank lines:                    %6d (%6.2f%%)\n", 				blank, 100 * blank / lines);
	printf("Comment lines:                  %6d (%6.2f%%)\n",				comments, 100 * comments / lines);
	whitespace = blank + comments;
	printf("Total whitespace/comment lines: %6d (%6.2f%%)\n",				whitespace, 100 * whitespace / lines);
	printf("\n");
	printf("Predicate declaration lines:    %6d (%6.2f%%)\n",				preds, 100 * preds / lines);
	printf("Mode declaration lines:         %6d (%6.2f%%)\n",				modes, 100 * modes / lines);
	printf("Type declaration lines:         %6d (%6.2f%%)\n",				types, 100 * types / lines);
	printf("Inst declaration lines:         %6d (%6.2f%%)\n",				insts, 100 * insts / lines);
	other_decls = decls - preds - modes - types - insts;
	printf("Module declaration lines:       %6d (%6.2f%%)\n",				other_decls, 100 * other_decls / lines);
	printf("Total declaration lines:        %6d (%6.2f%%)\n",				decls, 100 * decls / lines);
	printf("\n");
	code = lines - whitespace - decls;
	printf("Code lines:                     %6d (%6.2f%%)\n",				code, 100 * code / lines);
	printf("\n");
	printf("Total number of lines:          %6d (%6.2f%%)\n", lines, 100);
}
