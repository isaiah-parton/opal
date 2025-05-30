package components

import ".."

Chip_Descriptor :: struct {
	using base: opal.Node_Descriptor,
	selected:   bool,
}

add_chip :: proc(text: string) -> opal.Node_Result {
	using opal
	self := add_node(
		&{
			background = Color{255, 255, 255, 50},
			stroke = theme.border_color,
			stroke_width = 1,
			padding = {12, 3, 12, 3},
			fit = 1,
			text = text,
			font_size = 12,
			foreground = Color{255, 255, 255, 255},
		},
	).?
	self.radius = self.size.y / 2
	return self
}
