package components

import ".."
import tw "../tailwind_colors"

Theme :: struct {
	font:            ^opal.Font,
	icon_font:       ^opal.Font,
	radius_small:    f32,
	radius_big:      f32,
	color:           Colors,
	base_size:       [2]f32,
	animation_time:  f32,
	font_size_small: f32,
}

Colors :: struct {
	border:               opal.Color,
	primary:              opal.Color,
	primary_foreground:   opal.Color,
	secondary:            opal.Color,
	secondary_foreground: opal.Color,
	secondary_strong:     opal.Color,
	accent:               opal.Color,
	background:           opal.Color,
	base_strong:          opal.Color,
}

theme: Theme = {
	base_size = 16,
	radius_small = 6,
	radius_big = 12,
	font_size_small = 14,
	color = {
		background = tw.NEUTRAL_900,
		base_strong = tw.NEUTRAL_950,
		accent = tw.BLUE_500,
		primary = tw.EMERALD_600,
		primary_foreground = tw.NEUTRAL_950,
		secondary = tw.NEUTRAL_700,
		secondary_foreground = tw.NEUTRAL_950,
		secondary_strong = tw.NEUTRAL_600,
		border = tw.NEUTRAL_500,
	},
}

