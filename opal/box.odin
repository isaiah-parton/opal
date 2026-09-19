package opal

import "core:math/linalg"

Box :: struct {
	min: Vector2,
	max: Vector2
}

box_width :: proc(box: Box) -> f32 {
	return box.max.x - box.min.x
}
box_height :: proc(box: Box) -> f32 {
	return box.max.y - box.min.y
}
box_center_x :: proc(box: Box) -> f32 {
	return (box.min.x + box.max.x) * 0.5
}
box_center_y :: proc(box: Box) -> f32 {
	return (box.min.y + box.max.y) * 0.5
}

box_size :: proc(box: Box) -> [2]f32 {
	return box.max - box.min
}

size_ratio :: proc(size: [2]f32, ratio: [2]f32) -> [2]f32 {
	return [2]f32 {
		max(size.x, size.y * (ratio.x / ratio.y)),
		max(size.y, size.x * (ratio.y / ratio.x)),
	}
}

box_shrink :: proc(self: Box, amount: f32) -> Box {
	return {self.min + amount, self.max - amount}
}

box_is_real :: proc(box: Box) -> bool {
	return box.min.x < box.max.x && box.min.y < box.max.y
}

// If `a` is inside of `b`
point_in_box :: proc(point: [2]f32, box: Box) -> bool {
	return(
		(point.x >= box.min.x) &&
		(point.x <= box.max.x) &&
		(point.y >= box.min.y) &&
		(point.y <= box.max.y) \
	)
}

// If `a` is touching `b`
box_overlaps_other :: proc(self, other: Box) -> bool {
	return(
		(self.max.x >= other.min.x) &&
		(self.min.x <= other.max.x) &&
		(self.max.y >= other.min.y) &&
		(self.min.y <= other.max.y) \
	)
}

// If `a` is contained entirely in `b`
box_contains_other :: proc(self, other: Box) -> bool {
	return(
		(self.min.x >= other.min.x) &&
		(self.max.x <= other.max.x) &&
		(self.min.y >= other.min.y) &&
		(self.max.y <= other.max.y) \
	)
}

// Get the clip status of a box inside another
box_get_clip :: proc(self, other: Box) -> Clip {
	if self.min.x >= other.min.x &&
	   self.max.x <= other.max.x &&
	   self.min.y >= other.min.y &&
	   self.max.y <= other.max.y {
		return .None
	}
	if self.min.x > other.max.x ||
	   self.max.x < other.min.x ||
	   self.min.y > other.max.y ||
	   self.max.y < other.min.y {
		return .Full
	}
	return .Partial
}

// Get the clip status of a box inside a rounded box
box_get_rounded_clip :: proc(self, other: Box, radius: f32) -> Clip {
	if self.min.x >= other.min.x + radius &&
	   self.max.x <= other.max.x - radius &&
	   self.min.y >= other.min.y + radius &&
	   self.max.y <= other.max.y - radius {
		return .None
	}
	if self.min.x > other.max.x ||
	   self.max.x < other.min.x ||
	   self.min.y > other.max.y ||
	   self.max.y < other.min.y {
		return .Full
	}
	return .Partial
}

// Grow a box to fit another box inside it
box_grow_to_fit :: proc(self: ^Box, other: Box) {
	self.min = linalg.min(self.min, other.min)
	self.max = linalg.max(self.max, other.max)
}

// Returns the box clamped inside another
box_clamped :: proc(self, other: Box) -> Box {
	return {linalg.max(self.min, other.min), linalg.min(self.max, other.max)}
}

// Snap a box to a whole number position
box_snap :: proc(self: ^Box) {
	size := self.max - self.min
	self.min = linalg.floor(self.min)
	self.max = self.min + linalg.floor(size)
}

box_floored :: proc(self: Box) -> Box {
	return Box{linalg.floor(self.min), linalg.floor(self.max)}
}

box_center :: proc(self: Box) -> [2]f32 {
	return {(self.min.x + self.max.x) * 0.5, (self.min.y + self.max.y) * 0.5}
}

box_cut_left :: proc(self: ^Box, amount: f32) -> (res: Box) {
	left := min(self.min.x + amount, self.max.x)
	res = {self.min, {left, self.max.y}}
	self.min.x = left
	return
}

box_cut_top :: proc(self: ^Box, amount: f32) -> (res: Box) {
	top := min(self.min.y + amount, self.max.y)
	res = {self.min, {self.max.x, top}}
	self.min.y = top
	return
}

box_cut_right :: proc(self: ^Box, amount: f32) -> (res: Box) {
	right := max(self.min.x, self.max.x - amount)
	res = {{right, self.min.y}, self.max}
	self.max.x = right
	return
}

box_cut_bottom :: proc(self: ^Box, amount: f32) -> (res: Box) {
	bottom := max(self.min.y, self.max.y - amount)
	res = {{self.min.x, bottom}, self.max}
	self.max.y = bottom
	return
}
