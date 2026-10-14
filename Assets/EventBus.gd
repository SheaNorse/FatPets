extends Node

# Requests the confirmation overlay to show up for a target slot
signal delete_confirmation_requested(target_node: Node, pet_name: String)

# Fires when the user clicks the final "Delete" button inside the modal
signal delete_confirmed(target_node: Node)
