trigger LeadTrigger on Lead(before insert, before update) {
	 LeadLogicController.calculateLeadScore(Trigger.new);
}