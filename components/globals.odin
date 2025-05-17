package components

import ".."

Theme :: struct {
	icon_font:      ^opal.Font,
	border_color:   opal.Color,
	base_size:      [2]f32,
	animation_time: f32,
}

theme: Theme = {
	base_size = 16,
}
