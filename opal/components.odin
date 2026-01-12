package opal

import kn "../katana"
import tw "../tailwind_colors"

COMPONENT_TEXT_GAP :: 4
COMPONENT_CHECKBOX_SIZE :: 18
COMPONENT_FONT_SIZE :: 14

Checkbox_Descriptor :: struct {
	using base: Node_Descriptor,
	label:      string,
	value:      ^bool,
}

Checkbox_Result :: struct {
	node:    Maybe(^Node),
	toggled: bool,
}

add_checkbox :: proc(
	desc: ^Checkbox_Descriptor,
	loc := #caller_location,
) -> (
	result: Checkbox_Result,
) {
	assert(desc.value != nil)

	push_id(hash_loc(loc))
	defer pop_id()

	node := begin_node(&{sizing = {fit = 1}, gap = 4, radius = 4, interactive = true}).?
	if node.is_active && !node.was_active {
		desc.value^ = !desc.value^
	}
	node_update_transition(node, 1, node.is_hovered, 0.1)
	node_update_transition(node, 0, desc.value^, 0.2)
	node.background = kn.fade(tw.SLATE_200, 0.2 * node.transitions[1])
	{
		add_node(
			&{
				sizing = {exact = COMPONENT_CHECKBOX_SIZE},
				radius = 4,
				background = kn.mix(node.transitions[0], tw.SLATE_900, tw.WHITE),
			},
		)
		add_node(
			&{
				sizing = {fit = 1},
				text = desc.label,
				font = &global_ctx.default_font,
				font_size = COMPONENT_FONT_SIZE,
				foreground = tw.WHITE,
			},
		)
	}
	end_node()
	return
}

