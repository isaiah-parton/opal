package components

import ".."

import tw "../tailwind_colors"

do_button :: proc(label: union #no_nil {
		string,
		rune,
	}, font: ^opal.Font = nil, font_size: f32 = 12, radius: [4]f32 = 3, loc := #caller_location) -> bool {
	using opal
	self := add_node(
		&{
			padding = 3,
			radius = radius,
			fit = 1,
			text = label.(string) or_else string_from_rune(label.(rune)),
			font_size = font_size,
			foreground = tw.NEUTRAL_300,
			stroke = tw.BLUE_500,
			stroke_type = .Both,
			font = font,
			max_size = INFINITY,
			is_widget = true,
		},
		loc = loc,
	).?
	node_update_transition(self, 0, self.is_hovered, 0.1)
	node_update_transition(self, 1, self.is_active, 0.1)
	self.style.stroke_width = 2 * self.transitions[1]
	self.style.background = fade(tw.NEUTRAL_600, 0.3 + f32(i32(self.is_hovered)) * 0.3)
	assert(self != nil)
	return self.was_active && !self.is_active && self.is_hovered
}

do_window_button :: proc(icon: rune, color: opal.Color, loc := #caller_location) -> bool {
	using opal
	self := add_node(
		&{
			padding = 3,
			fit = 1,
			text = string_from_rune(icon),
			font_size = 20,
			foreground = tw.NEUTRAL_300,
			font = theme.icon_font,
			max_size = INFINITY,
			is_widget = true,
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
