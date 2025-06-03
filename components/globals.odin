package components

import ".."
import tw "../tailwind_colors"

Theme :: struct {
	icon_font:      ^opal.Font,
	color:          Colors,
	base_size:      [2]f32,
	animation_time: f32,
}

Colors :: struct {
	border:  opal.Color,
	primary: opal.Color,
}

theme: Theme = {
	base_size = 16,
	color = {primary = tw.NEUTRAL_100, border = tw.NEUTRAL_500},
}

