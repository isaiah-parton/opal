package components

import kn "../katana"
import "../opal"
import tw "../tailwind_colors"

Button_Descriptor :: struct {
	using base:  opal.Node_Descriptor,
	shade_color: opal.Color,
}

Button_Variant :: enum {
	Primary,
	Secondary,
}

make_button :: proc(label: union #no_nil {
		string,
		rune,
	}, variant: Button_Variant = .Secondary) -> Button_Descriptor {
	using opal

	desc := Button_Descriptor {
		padding = {7, 5, 7, 5},
		radius = theme.radius_small,
		sizing = {fit = 1, max = INFINITY},
		text = label.(string) or_else string_from_rune(label.(rune)),
		font_size = theme.font_size_small,
		foreground = tw.NEUTRAL_300,
		font = &theme.font,
		interactive = true,
		shade_color = fade(tw.BLACK, 0.1),
	}
	switch variant {
	case .Primary:
		desc.background = theme.color.primary
		desc.foreground = theme.color.primary_foreground
	case .Secondary:
		desc.background = theme.color.secondary
		desc.foreground = theme.color.secondary_foreground
	}
	return desc
}

add_button :: proc(desc: ^Button_Descriptor, loc := #caller_location) -> bool {
	using opal
	self := add_node(desc, loc = loc).?
	node_update_transition(self, 0, self.is_hovered, 0.1)
	node_update_transition(self, 1, self.is_active, 0.1)
	// self.style.stroke_width = 4 * self.transitions[1]
	// self.style.background = kn.blend_colors_time(
	// 	self.style.background.(Color),
	// 	desc.shade_color,
	// 	self.transitions[0],
	// )
	self.style.transform_origin = 0.5
	self.style.scale = 1 - 0.05 * self.transitions[1]
	assert(self != nil)
	return self.was_active && !self.is_active && self.is_hovered
}

do_window_button :: proc(icon: rune, color: opal.Color, loc := #caller_location) -> bool {
	using opal
	self := add_node(
		&{
			padding = 3,
			sizing = {fit = 1, max = INFINITY},
			text = string_from_rune(icon),
			font_size = 20,
			foreground = tw.NEUTRAL_300,
			font = &theme.icon_font,
			interactive = true,
		},
		loc = loc,
	).?
	node_update_transition(self, 0, self.is_hovered, 0.1)
	node_update_transition(self, 1, self.is_active, 0.1)
	self.style.background = fade(color, self.transitions[0])
	self.style.foreground = mix(self.transitions[0], tw.WHITE, tw.NEUTRAL_900)
	assert(self != nil)
	return self.was_active && !self.is_active && self.is_hovered
}

