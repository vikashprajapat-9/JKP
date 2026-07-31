trigger LeadTrigger on Lead(before insert, before update) {
	 LeadLogicController.performInitialOperations(Trigger.new, Trigger.oldMap);
}