class_name RmtWrapModifier
extends SkeletonModifier3D
## The Body Solve as a skeleton modifier: put it AFTER other modifiers (spring bones) and it pushes their results back out of
## the body every update. Spring chains (tails, ears) can only push their joints out of colliders, so a tail that sits tight
## between the legs still slips into them; this catches what the springs leave. Only `solver.movers` may move here, the rest
## of the body is already final.
##   var m := RmtWrapModifier.new(); m.solver = solver; skeleton.add_child(m)   # after the SpringBoneSimulator3D nodes

var solver: RmtBodySolve


func _process_modification() -> void:
	if solver != null:
		solver.solve(NAN)
