package components

import kn "../katana"
import "../opal"
import tw "../tailwind_colors"
import "core:math/ease"

//
// **Make a node descriptor for a toggle switch**
//
// `value` must still be valid when `end()` is called
//
add_toggle_switch :: proc(value: ^bool, loc := #caller_location) {
	using opal
	push_id(hash(loc));defer pop_id()
	base_size := [2]f32{45, 25}
	self := begin_node(
		&{
			sizing = {exact = base_size},
			radius = base_size.y / 2,
			background = tw.NEUTRAL_950,
			interactive = true,
		},
	).?
	begin_node(
		&{
			absolute = true,
			relative_offset = {self.transitions[0], 0},
			exact_offset = {-base_size.y * self.transitions[0], 0},
			sizing = {exact = base_size.y},
			padding = 2 + self.transitions[1],
		},
	)
	add_node(
		&{
			sizing = {max = INFINITY, grow = 1},
			radius = (base_size.y - 4) / 2,
			shadow_offset = {-1, 2},
			shadow_size = 4,
			shadow_color = fade(kn.BLACK, 0.5 * self.transitions[0]),
			background = mix(
				self.transitions[0],
				theme.color.secondary,
				theme.color.secondary_strong,
			),
		},
	)
	end_node()
	end_node()

	node_update_transition(self, 0, value^, 0.2)
	node_update_transition(self, 1, self.is_active, 0.1)
	self.style.background = mix(
		self.transitions[0],
		self.style.background.(Color),
		theme.color.secondary,
	)
	// self.style.stroke_width = 4 * self.transitions[1]
	if self.is_hovered && self.was_active && !self.is_active {
		value^ = !value^
	}
}

