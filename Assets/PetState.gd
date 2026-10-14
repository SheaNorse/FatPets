class_name PetState
extends Node

var pet: CharacterBody2D
var state_machine: PetStateMachine

func enter() -> void:
	pass

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

func allows_wandering() -> bool:
	return true

# Override this in custom states to return false when petting shouldn't be allowed
func allows_petting() -> bool:
	return false
