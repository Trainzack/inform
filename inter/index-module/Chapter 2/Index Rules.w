[IndexRules::] Index Rules.

Utility functions for indexing rules, rulebooks and activities.

@h Marked rulebooks and activities.
The Inter hierarchy likely contains numerous rulebooks and activities, and we
need to know which one is, for example, the "when play begins" rulebook. We don't
want to recognise this by its name, since that might cause problems if the source
language is not English. Instead, the Inform compiler marks certain special
rulebook or activity packages with an |^index_id| metadatum: for example, this
might be |"when_play_begins"|. Such markers are language-independent.

Given an inventory |inv| of the Inter hierarchy, then, the following functions
retrieve packages by marker text. This coild be done more efficiently with a
dictionary, but it's not used often enough to make it worth the work.

=
inter_package *IndexRules::find_rulebook(tree_inventory *inv, text_stream *marker) {
	for (int i=0; i<TreeLists::len(inv->rulebook_nodes); i++) {
		inter_package *pack = Inter::Package::defined_by_frame(inv->rulebook_nodes->list[i].node);
		if (Str::eq(marker, Metadata::read_optional_textual(pack, I"^index_id")))
			return pack;
	}
	return NULL;
}

inter_package *IndexRules::find_activity(tree_inventory *inv, text_stream *marker) {
	for (int i=0; i<TreeLists::len(inv->activity_nodes); i++) {
		inter_package *pack = Inter::Package::defined_by_frame(inv->activity_nodes->list[i].node);
		if (Str::eq(marker, Metadata::read_optional_textual(pack, I"^index_id")))
			return pack;
	}
	return NULL;
}

@h Rule contexts.
We sometimes want to index only some of the contents of a rulebook: those which
fit a particular "context". This structure abstracts that idea:

=
typedef struct rule_context {
	struct inter_package *action_context;
	struct simplified_scene *scene_context;
} rule_context;

@ Either the rules have to take effect with the given action, or during the
given scene:

=
rule_context IndexRules::action_context(inter_package *an) {
	rule_context rc;
	rc.action_context = an;
	rc.scene_context = NULL;
	return rc;
}
rule_context IndexRules::scene_context(simplified_scene *s) {
	rule_context rc;
	rc.action_context = NULL;
	rc.scene_context = s;
	return rc;
}

@ ...Or, of course, neither. This is the default rule context, and means there
is no restriction, so that we should be indexing the entire rulebook.

=
rule_context IndexRules::no_rule_context(void) {
	rule_context rc;
	rc.action_context = NULL;
	rc.scene_context = NULL;
	return rc;
}

@ To implement this, we need to know if the premiss for a given rule contains
explicit requirements matching the given context |rc|. This is something that
only the compiler can know for sure, so the compiler has marked the rule package
with |^action| and |^during| metadata to make it possible for us to decide now.

=
int IndexRules::phrase_fits_rule_context(inter_tree *I, inter_package *rule_pack,
	rule_context rc) {
	if (rule_pack == NULL) return FALSE;
	if (rc.action_context) {
		int passes = FALSE;
		inter_symbol *wanted = PackageTypes::get(I, I"_relevant_action");
		inter_tree_node *D = Inter::Packages::definition(rule_pack);
		LOOP_THROUGH_INTER_CHILDREN(C, D) {
			if (C->W.data[ID_IFLD] == PACKAGE_IST) {
				inter_package *rel_pack = Inter::Package::defined_by_frame(C);
				if (Inter::Packages::type(rel_pack) == wanted) {
					inter_symbol *act_ds = Metadata::read_symbol(rel_pack, I"^action");
					if (Inter::Packages::container(act_ds->definition) == rc.action_context)
						passes = TRUE;
				}
			}
		}
		if (passes == FALSE) return FALSE;
	}
	if (rc.scene_context) {
		inter_symbol *scene_symbol = Metadata::read_optional_symbol(rule_pack, I"^during");
		if (scene_symbol == NULL) return FALSE;
		if (Inter::Packages::container(scene_symbol->definition) !=
			rc.scene_context->pack) return FALSE;
	}
	return TRUE;
}

@ A rulebook is "conceptually empty" with respect to a context |rc| if it contains
no rules which fit |rc|:

=
int IndexRules::is_contextually_empty(inter_tree *I, inter_package *rb_pack, rule_context rc) {
	if (rb_pack) {
		inter_symbol *wanted = PackageTypes::get(I, I"_rulebook_entry");
		inter_tree_node *D = Inter::Packages::definition(rb_pack);
		LOOP_THROUGH_INTER_CHILDREN(C, D) {
			if (C->W.data[ID_IFLD] == PACKAGE_IST) {
				inter_package *entry = Inter::Package::defined_by_frame(C);
				if (Inter::Packages::type(entry) == wanted)
					if (IndexRules::phrase_fits_rule_context(I, entry, rc))
						return FALSE;
			}
		}
	}
	return TRUE;
}

@ Actual emptiness is easier to spot:

=
int IndexRules::is_empty(inter_tree *I, inter_package *rb_pack) {
	if ((rb_pack) && (IndexRules::no_rules(I, rb_pack) > 0)) return FALSE;
	return TRUE;
}

int IndexRules::no_rules(inter_tree *I, inter_package *rb_pack) {
	int N = 0;
	if (rb_pack) {
		inter_symbol *wanted = PackageTypes::get(I, I"_rulebook_entry");
		inter_tree_node *D = Inter::Packages::definition(rb_pack);
		LOOP_THROUGH_INTER_CHILDREN(C, D) {
			if (C->W.data[ID_IFLD] == PACKAGE_IST) {
				inter_package *entry = Inter::Package::defined_by_frame(C);
				if (Inter::Packages::type(entry) == wanted)
					N++;
			}
		}
	}
	return N;
}

@h Links between rules in rulebook listings.
A notation is used to show how rulebook sorting affected the placement of
adjacent rules in an index listing; but this notation can be temporarily
switched off:

=
int IX_show_index_links = TRUE;

void IndexRules::list_suppress_indexed_links(void) {
	IX_show_index_links = FALSE;
}

void IndexRules::list_resume_indexed_links(void) {
	IX_show_index_links = TRUE;
}

int IndexRules::showing_links(void) {
	return IX_show_index_links;
}

@h Unique extra-box IDs.

=
int RS_unique_xtra_no = 77777;
int IndexRules::extra_ID(void) {
	return RS_unique_xtra_no++;
}

@h Rulebook boxes.

@d RULEBOOK_BOX_COLOUR "e0e0e0"

=
void IndexRules::rulebook_box(OUTPUT_STREAM, tree_inventory *inv,
	text_stream *titling_text, text_stream *doc_link, inter_package *rb_pack,
	text_stream *disclaimer_instead, int indent, int place_in_expandable_box, localisation_dictionary *LD) {
	if (rb_pack == NULL) return;

	TEMPORARY_TEXT(textual_name)
	if (Str::len(titling_text) > 0) WRITE_TO(textual_name, "%S", titling_text);
	else Localisation::write_0(textual_name, LD, I"Index.Elements.RS.Nameless");
	string_position start = Str::start(textual_name);
	Str::put(start, Characters::tolower(Str::get(start)));

	int n = IndexRules::no_rules(inv->of_tree, rb_pack);

	if (place_in_expandable_box) {
		int expand_id = IndexRules::extra_ID();
		HTML::open_indented_p(OUT, indent+1, "tight");
		IndexUtilities::extra_link(OUT, expand_id);
		if (n == 0) HTML::begin_colour(OUT, I"808080");
		WRITE("%S", textual_name);
		@<Add links and such to the titling@>;
		WRITE(" (%d rule%s)", n, (n==1)?"":"s");
		if (n == 0) HTML::end_colour(OUT);
		HTML_CLOSE("p");
		IndexUtilities::extra_div_open(OUT, expand_id, indent+1, RULEBOOK_BOX_COLOUR);
		@<Index the contents of the rulebook box@>;
		IndexUtilities::extra_div_close(OUT, RULEBOOK_BOX_COLOUR);
	} else {
		HTML::open_indented_p(OUT, indent, "");
		HTML::open_coloured_box(OUT, RULEBOOK_BOX_COLOUR, ROUND_BOX_TOP+ROUND_BOX_BOTTOM);
		@<Index the contents of the rulebook box@>;
		HTML::close_coloured_box(OUT, RULEBOOK_BOX_COLOUR, ROUND_BOX_TOP+ROUND_BOX_BOTTOM);
		HTML_CLOSE("p");
	}
	DISCARD_TEXT(textual_name)
}

@<Index the contents of the rulebook box@> =
	HTML::begin_html_table(OUT, NULL, TRUE, 0, 4, 0, 0, 0);
	HTML::first_html_column(OUT, 0);
	HTML::open_indented_p(OUT, 1, "tight");
	WRITE("<b>%S</b>", textual_name);
	@<Add links and such to the titling@>;
	HTML_CLOSE("p");
	HTML::next_html_column_right_justified(OUT, 0);
	HTML::open_indented_p(OUT, 1, "tight");
	PasteButtons::paste_text(OUT, textual_name);
	WRITE("&nbsp;<i>name</i>");
	HTML_CLOSE("p");
	HTML::end_html_row(OUT);
	HTML::end_html_table(OUT);

	if (n == 0) {
		HTML::open_indented_p(OUT, 2, "tight");
		Localisation::write_0(OUT, LD, I"Index.Elements.RS.Empty");
		HTML_CLOSE("p");
	} else if (disclaimer_instead) {
		HTML::open_indented_p(OUT, 2, "tight"); WRITE("%S", disclaimer_instead); HTML_CLOSE("p");
	} else {
		IndexRules::rulebook_list(OUT, inv->of_tree, rb_pack, NULL, IndexRules::no_rule_context(), LD);
	}

@<Add links and such to the titling@> =
	if (Str::len(doc_link) > 0) IndexUtilities::DocReferences::link(OUT, doc_link);
	WRITE(" ... %S", Metadata::read_optional_textual(rb_pack, I"^focus"));
	int at = (int) Metadata::read_optional_numeric(rb_pack, I"^at");
	if (at > 0) IndexUtilities::link(OUT, at);

@h Two ways to list a rulebook.
Firstly, the whole contents:

=
int IndexRules::rulebook_list(OUTPUT_STREAM, inter_tree *I, inter_package *rb_pack,
	text_stream *billing, rule_context rc, localisation_dictionary *LD) {
	int resp_count = 0;
	int t = IndexRules::index_rulebook_inner(OUT, 0, I, rb_pack, billing, rc, &resp_count, LD);
	if (t > 0) HTML_CLOSE("p");
	return resp_count;
}

@ Secondly, just the contents relevant to a given action:

=
int IndexRules::index_action_rules(OUTPUT_STREAM, tree_inventory *inv, inter_package *an,
	inter_package *rb, text_stream *key, text_stream *desc, localisation_dictionary *LD) {
	int resp_count = 0;
	IndexRules::list_suppress_indexed_links();
	int t = IndexRules::index_rulebook_inner(OUT, 0, inv->of_tree,
		IndexRules::find_rulebook(inv, key), desc,
		IndexRules::action_context(an), &resp_count, LD);
	if (rb) t += IndexRules::index_rulebook_inner(OUT, t, inv->of_tree, rb, desc,
		IndexRules::no_rule_context(), &resp_count, LD);
	if (t > 0) HTML_CLOSE("p");
	IndexRules::list_resume_indexed_links();
	return resp_count;
}

@ Either way, we end up here:

=
int IndexRules::index_rulebook_inner(OUTPUT_STREAM, int initial_t, inter_tree *I,
	inter_package *rb_pack, text_stream *billing, rule_context rc, int *resp_count,
	localisation_dictionary *LD) {
	int suppress_outcome = FALSE, count = initial_t;
	if (rb_pack == NULL) return 0;
	if (Str::len(billing) > 0) {
		if (rc.action_context) suppress_outcome = TRUE;
		if (IndexRules::is_contextually_empty(I, rb_pack, rc)) suppress_outcome = TRUE;
	}
	inter_package *prev = NULL;
	inter_symbol *wanted = PackageTypes::get(I, I"_rulebook_entry");
	inter_tree_node *D = Inter::Packages::definition(rb_pack);
	LOOP_THROUGH_INTER_CHILDREN(C, D) {
		if (C->W.data[ID_IFLD] == PACKAGE_IST) {
			inter_package *entry = Inter::Package::defined_by_frame(C);
			if (Inter::Packages::type(entry) == wanted) {
				if (IndexRules::phrase_fits_rule_context(I, entry, rc)) {
					if (count++ == 0) HTML::open_indented_p(OUT, 2, "indent");
					else WRITE("<br>");
					if ((Str::len(billing) > 0) && (IndexRules::showing_links()))
						@<Show a linkage icon@>;
					WRITE("%S", billing);
					WRITE("&nbsp;&nbsp;&nbsp;&nbsp;");
					*resp_count += IndexRules::index_rule(OUT, I, entry, rb_pack, rc, LD);
				}
				prev = entry;
			}
		}
	}
	if (count > 0) HTML_CLOSE("p");
	if (suppress_outcome == FALSE) IndexRules::index_outcomes(OUT, I, rb_pack, LD);
	IndexRules::rb_index_placements(OUT, I, rb_pack, LD);
	return count;
}

@ As noted somewhere above, there's a notation for marking the relative specificity
of adjacent rules in a listing:

@<Show a linkage icon@> =
	text_stream *icon_name = NULL; /* redundant assignment to appease |gcc -O2| */
	if ((prev == NULL) ||
		(Str::len(Metadata::read_optional_textual(prev, I"^tooltip")) == 0)) {
		HTML::icon_with_tooltip(OUT, I"inform:/doc_images/rulenone.png",
			I"start of rulebook", NULL);
	} else {
		switch (Metadata::read_optional_numeric(prev, I"^specificity")) {
			case 0: icon_name = I"inform:/doc_images/ruleless.png"; break;
			case 1: icon_name = I"inform:/doc_images/ruleequal.png"; break;
			case 2: icon_name = I"inform:/doc_images/rulemore.png"; break;
			default: internal_error("unknown rule specificity");
		}
		HTML::icon_with_tooltip(OUT, icon_name,
			Metadata::read_optional_textual(prev, I"^tooltip"),
			Metadata::read_optional_textual(prev, I"^law"));
	}

@h Listing a single rule.

=
int IndexRules::index_rule(OUTPUT_STREAM, inter_tree *I, inter_package *R,
	inter_package *owner, rule_context rc, localisation_dictionary *LD) {
	int no_responses_indexed = 0;
	int response_box_id = IndexRules::extra_ID();
	text_stream *name = Metadata::read_optional_textual(R, I"^name");
	text_stream *italicised_text = Metadata::read_optional_textual(R, I"^index_name");
	text_stream *first_line = Metadata::read_optional_textual(R, I"^first_line");
	if (Str::len(italicised_text) > 0) @<Index the italicised text to do with the rule@>;
	if (Str::len(name) > 0) @<Index the rule name along with Javascript buttons@>;
	if ((Str::len(italicised_text) == 0) &&
		(Str::len(name) == 0) && (Str::len(first_line) > 0))
		@<Index some text extracted from the first line of the otherwise anonymous rule@>;
	@<Index a link to the first line of the rule's definition@>;
	@<Index the small type rule numbering@>;
	@<Index any applicability conditions@>;
	@<Index any response texts in the rule@>;
	return no_responses_indexed;
}

@<Index the italicised text to do with the rule@> =
	WRITE("<i>%S", italicised_text);
	if (rc.scene_context) {
		WRITE(" ");
		Localisation::write_1(OUT, LD, I"Index.Elements.RS.During",
			PlotElement::scene_name(rc.scene_context));
	}
	WRITE("</i>&nbsp;&nbsp;");

@

@d MAX_PASTEABLE_RULE_NAME_LENGTH 500

@<Index the rule name along with Javascript buttons@> =
	HTML::begin_colour(OUT, I"800000");
	WRITE("%S", name);
	HTML::end_colour(OUT);
	WRITE("&nbsp;&nbsp;");

	TEMPORARY_TEXT(S)
	WRITE_TO(S, "%S", name);
	PasteButtons::paste_text(OUT, S);
	WRITE("&nbsp;<i>name</i> ");

	Str::clear(S);
	Localisation::write_2(S, LD, I"Index.Elements.RS.Response", name,
		Metadata::read_optional_textual(owner, I"^printed_name"));
	PasteButtons::paste_text(OUT, S);
	WRITE("&nbsp;<i>unlist</i>");
	DISCARD_TEXT(S)

	inter_symbol *R_symbol = Metadata::read_optional_symbol(R, I"^rule");
	if (R_symbol) {
		int c = 0;
		inter_symbol *wanted = PackageTypes::get(I, I"_response");
		inter_tree_node *D = Inter::Packages::definition(R);
		LOOP_THROUGH_INTER_CHILDREN(C, D) {
			if (C->W.data[ID_IFLD] == PACKAGE_IST) {
				inter_package *entry = Inter::Package::defined_by_frame(C);
				if (Inter::Packages::type(entry) == wanted)
					c++;
			}
		}
		if (c > 0) {
			WRITE("&nbsp;&nbsp;");
			IndexUtilities::extra_link_with(OUT, response_box_id, "responses");
			WRITE("%d", c);
		}
	}

@<Index any response texts in the rule@> =
	inter_symbol *R_symbol = Metadata::read_optional_symbol(R, I"^rule");
	if (R_symbol) {
		int c = 0;
		inter_symbol *wanted = PackageTypes::get(I, I"_response");
		inter_tree_node *D = Inter::Packages::definition(R);
		LOOP_THROUGH_INTER_CHILDREN(C, D) {
			if (C->W.data[ID_IFLD] == PACKAGE_IST) {
				inter_package *entry = Inter::Package::defined_by_frame(C);
				if (Inter::Packages::type(entry) == wanted) {
					if (c == 0) IndexUtilities::extra_div_open_nested(OUT, response_box_id, 2);
					else HTML_TAG("br");
					IndexRules::index_response(OUT, R, entry, LD);
					c++;
				}
			}
		}
		if (c > 0) IndexUtilities::extra_div_close_nested(OUT);
		no_responses_indexed = c;
	}

@<Index some text extracted from the first line of the otherwise anonymous rule@> =
	WRITE("(%S)", first_line);

@<Index a link to the first line of the rule's definition@> =
	int at = (int) Metadata::read_optional_numeric(R, I"^at");
	if (at > 0) IndexUtilities::link(OUT, at);

@<Index the small type rule numbering@> =
	inter_ti id = Metadata::read_optional_numeric(R, I"^index_number");
	if (id > 0) {
		WRITE(" ");
		HTML_OPEN_WITH("span", "class=\"smaller\"");
		if (id >= 2) WRITE("%d", id - 2); else WRITE("primitive");
		HTML_CLOSE("span");
	}

@<Index any applicability conditions@> =
	inter_symbol *R_symbol = Metadata::read_optional_symbol(R, I"^rule");
	if (R_symbol) {
		inter_symbol *wanted = PackageTypes::get(I, I"_applicability_condition");
		inter_tree_node *D = Inter::Packages::definition(R);
		LOOP_THROUGH_INTER_CHILDREN(C, D) {
			if (C->W.data[ID_IFLD] == PACKAGE_IST) {
				inter_package *entry = Inter::Package::defined_by_frame(C);
				if (Inter::Packages::type(entry) == wanted) {
					HTML_TAG("br");
					int at = (int) Metadata::read_optional_numeric(entry, I"^at");
					if (at > 0) IndexUtilities::link(OUT, at);
					WRITE("&nbsp;%S", Metadata::read_textual(entry, I"^index_text"));
				}
			}
		}
	}

@ When we index a response, we also provide a paste button for the source
text to assert a change:

=
void IndexRules::index_response(OUTPUT_STREAM, inter_package *rule_pack,
	inter_package *resp_pack, localisation_dictionary *LD) {
	int marker = (int) Metadata::read_numeric(resp_pack, I"^marker");
	text_stream *text = Metadata::read_textual(resp_pack, I"^index_text");
	WRITE("&nbsp;&nbsp;&nbsp;&nbsp;");
	HTML_OPEN_WITH("span",
		"style=\"color: #ffffff; "
		"font-family: 'Courier New', Courier, monospace; background-color: #8080ff;\"");
	WRITE("&nbsp;&nbsp;%c&nbsp;&nbsp; ", 'A' + marker);
	HTML_CLOSE("span");
	HTML_OPEN_WITH("span", "style=\"color: #000066;\"");
	WRITE("%S", text);
	HTML_CLOSE("span");
	WRITE("&nbsp;&nbsp;");
	TEMPORARY_TEXT(S)
	WRITE_TO(S, "%S response (%c)",
		Metadata::read_textual(rule_pack, I"^name"), 'A' + marker);
	PasteButtons::paste_text(OUT, S);
	WRITE("&nbsp;<i>name</i>");
	WRITE("&nbsp;");
	Str::clear(S);
	TEMPORARY_TEXT(letter)
	WRITE_TO(letter, "%c", 'A' + marker);
	Localisation::write_2(S, LD, I"Index.Elements.RS.Response",
		Metadata::read_textual(rule_pack, I"^name"), letter);
	PasteButtons::paste_text(OUT, S);
	WRITE("&nbsp;<i>set</i>");
	DISCARD_TEXT(letter)
	DISCARD_TEXT(S)
}

@ =
void IndexRules::index_outcomes(OUTPUT_STREAM, inter_tree *I, inter_package *rb_pack,
	localisation_dictionary *LD) {
	inter_symbol *wanted = PackageTypes::get(I, I"_rulebook_outcome");
	inter_tree_node *D = Inter::Packages::definition(rb_pack);
	LOOP_THROUGH_INTER_CHILDREN(C, D) {
		if (C->W.data[ID_IFLD] == PACKAGE_IST) {
			inter_package *entry = Inter::Package::defined_by_frame(C);
			if (Inter::Packages::type(entry) == wanted) {	
				HTML::open_indented_p(OUT, 2, "hanging");
				WRITE("<i>");
				Localisation::write_0(OUT, LD, I"Index.Elements.RS.Outcome");
				WRITE("</i>&nbsp;&nbsp;");
				int is_def = (int) Metadata::read_optional_numeric(entry, I"^is_default");
				if (is_def) WRITE("<b>");
				WRITE("%S", Metadata::read_optional_textual(entry, I"^text"));
				if (is_def) WRITE("</b> (default)");
				WRITE(" - <i>");
				if (Metadata::read_optional_numeric(entry, I"^succeeds"))
					Localisation::write_0(OUT, LD, I"Index.Elements.RS.Success");
				else if (Metadata::read_optional_numeric(entry, I"^fails"))
					Localisation::write_0(OUT, LD, I"Index.Elements.RS.Failure");
				else
					Localisation::write_0(OUT, LD, I"Index.Elements.RS.NoOutcome");
				WRITE("</i>");
				HTML_CLOSE("p");
			}
		}
	}

	if (Metadata::read_optional_numeric(rb_pack, I"^default_succeeds")) {
		HTML::open_indented_p(OUT, 2, "hanging");
		WRITE("<i>");
		Localisation::write_0(OUT, LD, I"Index.Elements.RS.DefaultSuccess");
		WRITE("</i>");
		HTML_CLOSE("p");
	}
	if (Metadata::read_optional_numeric(rb_pack, I"^default_fails")) {
		HTML::open_indented_p(OUT, 2, "hanging");
		WRITE("<i>");
		Localisation::write_0(OUT, LD, I"Index.Elements.RS.DefaultFailure");
		WRITE("</i>");
		HTML_CLOSE("p");
	}
}

void IndexRules::rb_index_placements(OUTPUT_STREAM, inter_tree *I, inter_package *rb_pack,
	localisation_dictionary *LD) {
	inter_symbol *wanted = PackageTypes::get(I, I"_rulebook_placement");
	inter_tree_node *D = Inter::Packages::definition(rb_pack);
	LOOP_THROUGH_INTER_CHILDREN(C, D) {
		if (C->W.data[ID_IFLD] == PACKAGE_IST) {
			inter_package *entry = Inter::Package::defined_by_frame(C);
			if (Inter::Packages::type(entry) == wanted) {	
				WRITE("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;");
				HTML_OPEN_WITH("span", "class=\"smaller\"");
				WRITE("<i>NB:</i> %S", Metadata::read_optional_textual(entry, I"^text"));
				int at = (int) Metadata::read_optional_numeric(entry, I"^at");
				if (at > 0) IndexUtilities::link(OUT, at);
				HTML_CLOSE("span");
				HTML_TAG("br");
			}
		}
	}
}

@h Activity boxes.
This is all just meant to convey visually that the three constituent rulebooks
of an activity are part of a single construct:

@d ACTIVITY_BOX_COLOUR "e8e0c0"

=
void IndexRules::activity_box(OUTPUT_STREAM, inter_tree *I, inter_package *av_pack,
	int indent, localisation_dictionary *LD) {
	text_stream *doc_link = Metadata::read_optional_textual(av_pack, I"^documentation");
	int expand_id = IndexRules::extra_ID();

	inter_symbol *before_s = Metadata::read_symbol(av_pack, I"^before_rulebook");
	inter_symbol *for_s = Metadata::read_symbol(av_pack, I"^for_rulebook");
	inter_symbol *after_s = Metadata::read_symbol(av_pack, I"^after_rulebook");
	inter_package *before_pack = Inter::Packages::container(before_s->definition);
	inter_package *for_pack = Inter::Packages::container(for_s->definition);
	inter_package *after_pack = Inter::Packages::container(after_s->definition);

	int n = IndexRules::no_rules(I, before_pack) +
			IndexRules::no_rules(I, for_pack) +
			IndexRules::no_rules(I, after_pack);

	TEMPORARY_TEXT(textual_name)
	text_stream *name = Metadata::read_optional_textual(av_pack, I"^name");
	if (Str::len(name) > 0) WRITE_TO(textual_name, "%S", name);
	else WRITE_TO(textual_name, "nameless");
	string_position start = Str::start(textual_name);
	Str::put(start, Characters::tolower(Str::get(start)));

	HTML::open_indented_p(OUT, indent+1, "tight");
	IndexUtilities::extra_link(OUT, expand_id);
	if (n == 0) HTML::begin_colour(OUT, I"808080");
	WRITE("%S", textual_name);
	@<Write the titling line of an activity rules box@>;
	WRITE(" (%d rule%s)", n, (n==1)?"":"s");
	if (n == 0) HTML::end_colour(OUT);
	HTML_CLOSE("p");

	IndexUtilities::extra_div_open(OUT, expand_id, indent+1, ACTIVITY_BOX_COLOUR);

	HTML::begin_html_table(OUT, NULL, TRUE, 0, 4, 0, 0, 0);
	HTML::first_html_column(OUT, 0);

	HTML::open_indented_p(OUT, 1, "tight");
	WRITE("<b>%S</b>", textual_name);
	@<Write the titling line of an activity rules box@>;
	HTML_CLOSE("p");

	HTML::next_html_column_right_justified(OUT, 0);

	HTML::open_indented_p(OUT, 1, "tight");

	TEMPORARY_TEXT(skeleton)
	Localisation::write_1(skeleton, LD, I"Index.Elements.RS.BeforeActivity", textual_name);
	PasteButtons::paste_text(OUT, skeleton);
	WRITE(":&nbsp;<i>b</i> ");
	Str::clear(skeleton);
	Localisation::write_1(skeleton, LD, I"Index.Elements.RS.ForActivity", textual_name);
	PasteButtons::paste_text(OUT, skeleton);
	WRITE(":&nbsp;<i>f</i> ");
	Str::clear(skeleton);
	Localisation::write_1(skeleton, LD, I"Index.Elements.RS.AfterActivity", textual_name);
	PasteButtons::paste_text(OUT, skeleton);
	WRITE(":&nbsp;<i>a</i>");
	DISCARD_TEXT(skeleton)

	HTML_CLOSE("p");
	DISCARD_TEXT(textual_name)

	HTML::end_html_row(OUT);
	HTML::end_html_table(OUT);

	IndexRules::rulebook_list(OUT, I, before_pack, I"before", IndexRules::no_rule_context(), LD);
	IndexRules::rulebook_list(OUT, I, for_pack, I"for", IndexRules::no_rule_context(), LD);
	IndexRules::rulebook_list(OUT, I, after_pack, I"after", IndexRules::no_rule_context(), LD);

	inter_symbol *wanted = PackageTypes::get(I, I"_activity_xref");
	inter_tree_node *D = Inter::Packages::definition(av_pack);
	LOOP_THROUGH_INTER_CHILDREN(C, D) {
		if (C->W.data[ID_IFLD] == PACKAGE_IST) {
			inter_package *entry = Inter::Package::defined_by_frame(C);
			if (Inter::Packages::type(entry) == wanted) {	
				HTML::open_indented_p(OUT, 2, "tight");
				WRITE("NB: %S", Metadata::read_optional_textual(entry, I"^text"));
				int at = (int) Metadata::read_optional_numeric(entry, I"^at");
				if (at > 0) IndexUtilities::link(OUT, at);
				HTML_CLOSE("p");
			}
		}
	}

	IndexUtilities::extra_div_close(OUT, ACTIVITY_BOX_COLOUR);
}

@<Write the titling line of an activity rules box@> =
	if (Str::len(doc_link) > 0) IndexUtilities::DocReferences::link(OUT, doc_link);
	WRITE(" ... ");
	Localisation::write_0(OUT, LD, I"Index.Elements.RS.Activity");
	int at = (int) Metadata::read_optional_numeric(av_pack, I"^at");
	if (at > 0) IndexUtilities::link(OUT, at);