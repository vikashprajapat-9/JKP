@IsTest
private class CommissionCatalogTest {

    private static Commission_Designation__mdt designation(String developerName, Integer position, Boolean active) {
        return (Commission_Designation__mdt) CommissionTestData.metadataRecord(Commission_Designation__mdt.class, 'Commission_Designation__mdt',
            new Map<String, Object>{ 'DeveloperName' => developerName, 'MasterLabel' => developerName + ' label', 'Order__c' => position, 'Active__c' => active });
    }

    @IsTest
    static void injectedCatalogIsReadInOrder() {
        CommissionTestData.useCatalog();

        List<CommissionDto.Designation> designations = CommissionCatalog.designations();
        System.assertEquals(7, designations.size(), 'Seven designations are injected');
        System.assertEquals('Sales_Advisor', designations[0].key, 'Designations come by their order');
        System.assertEquals('Referrer', designations[6].key, 'The referral fee is the last designation');
        System.assertEquals('Sales Advisor', designations[0].label, 'The label is the record label');
        System.assert(designations[0].userRoles.contains(CommissionTestData.ROLE_ADVISOR.toLowerCase()), 'Role names are kept in lower case');

        CommissionDto.Designation referrer = CommissionCatalog.designationByKey().get('Referrer');
        System.assertEquals('Flat', referrer.rateType, 'The referral fee is a flat amount');
        System.assertEquals('Single', referrer.split, 'The referral fee has one fixed payout event');
        System.assertEquals('SPA_Signing', referrer.fixedTrigger, 'The fixed payout event is copied');
        System.assertEquals('SPA signing date', referrer.fixedTriggerLabel, 'The label of the fixed payout event is filled from the events');
        System.assertEquals('Sales_Advisor', CommissionCatalog.designationByKey().get('Senior_Manager_Advisor').aggregateOf, 'A senior manager counts the advisors');

        List<CommissionDto.TriggerOption> events = CommissionCatalog.triggers();
        System.assertEquals(9, events.size(), 'Nine payout events are injected');
        System.assertEquals('SPA_Signing', events[0].key, 'Payout events come by their order');
        CommissionDto.TriggerOption percentPaid = CommissionCatalog.triggerByKey().get('Percent_Of_Price_Paid');
        System.assertEquals('Percent', percentPaid.parameterType, 'The event needs a percentage');
        System.assertEquals('PERCENT', percentPaid.orderGroup, 'The order group is copied');
        System.assertEquals(new List<String>{ 'Mid' }, percentPaid.stageTypes, 'The event is for Mid stages only');
        System.assertEquals('None', CommissionCatalog.triggerByKey().get('Handover').parameterType, 'An event without a parameter says None');

        System.assertEquals('Commission_Config_Approval', CommissionCatalog.setting().Approval_Process__c, 'The injected setting is returned');
    }

    @IsTest
    static void inactiveRecordsAreLeftOutAndTheRestIsSorted() {
        CommissionTestData.useCatalog();
        CommissionCatalog.testDesignations = new List<Commission_Designation__mdt>{
            designation('Second', 2, true), designation('Switched_Off', 0, false), designation('No_Order', null, true), designation('First', 1, true)
        };
        List<CommissionDto.Designation> designations = CommissionCatalog.designations();
        System.assertEquals(3, designations.size(), 'An inactive designation is left out');
        System.assertEquals('First', designations[0].key, 'Sorted by order');
        System.assertEquals('Second', designations[1].key, 'Sorted by order');
        System.assertEquals('No_Order', designations[2].key, 'A designation without an order comes last');
        System.assertEquals(0, designations[0].userRoles.size(), 'No roles when none are named');

        CommissionCatalog.testTriggers = new List<Commission_Trigger__mdt>{
            (Commission_Trigger__mdt) CommissionTestData.metadataRecord(Commission_Trigger__mdt.class, 'Commission_Trigger__mdt',
                new Map<String, Object>{ 'DeveloperName' => 'Both', 'MasterLabel' => 'Both ends', 'Stage_Types__c' => 'Initial; Final', 'Order__c' => 2, 'Active__c' => true }),
            (Commission_Trigger__mdt) CommissionTestData.metadataRecord(Commission_Trigger__mdt.class, 'Commission_Trigger__mdt',
                new Map<String, Object>{ 'DeveloperName' => 'Gone', 'MasterLabel' => 'Gone', 'Stage_Types__c' => 'Mid', 'Order__c' => 1, 'Active__c' => false })
        };
        List<CommissionDto.TriggerOption> events = CommissionCatalog.triggers();
        System.assertEquals(1, events.size(), 'An inactive payout event is left out');
        System.assertEquals(new List<String>{ 'Initial', 'Final' }, events[0].stageTypes, 'Stage types are split and trimmed');
        System.assertEquals('None', events[0].parameterType, 'A blank parameter type reads None');
    }

    @IsTest
    static void forScreenCarriesWhatAScreenNeeds() {
        CommissionTestData.useCatalog();
        insert new Payment_Schedule_Master__c(Name = 'On booking', Installment_Sequence__c = 1);

        CommissionDto.Catalog catalog = CommissionCatalog.forScreen();
        System.assertEquals(7, catalog.designations.size(), 'Designations are on the catalog');
        System.assertEquals(9, catalog.triggers.size(), 'Payout events are on the catalog');
        System.assertEquals(true, catalog.settings.finalStageRequired, 'The Final stage is required in the test setting');
        System.assertEquals(7, catalog.settings.expiryNoticeDays, 'The notice days are copied');
        System.assertEquals('LKR', catalog.settings.currencyCode, 'The currency code is copied');
        System.assertEquals(1, catalog.installments.size(), 'Every Payment Schedule Master row is listed');
        System.assertEquals('On booking', catalog.installments[0].name, 'The instalment name is copied');
        System.assertEquals(1, catalog.installments[0].sequence.intValue(), 'The instalment sequence is copied');
        System.assertEquals(2, catalog.targetBases.size(), 'Units and Value');
        System.assertEquals(System.Label.Commission_Target_Basis_Units, catalog.targetBases[0].label, 'Options carry their label');
        System.assertEquals(1, catalog.targetPeriods.size(), 'Only the periods named in the setting are offered');
        System.assertEquals('Configuration Period', catalog.targetPeriods[0].value, 'The stored value of the period');
        System.assertEquals(2, catalog.exceedModes.size(), 'Marginal and Retrospective');

        CommissionTestData.setSetting(new Map<String, Object>{ 'Target_Periods__c' => 'month; YEAR', 'Final_Stage_Required__c' => false });
        catalog = CommissionCatalog.forScreen();
        System.assertEquals(2, catalog.targetPeriods.size(), 'The setting decides the periods, whatever the case');
        System.assertEquals(false, catalog.settings.finalStageRequired, 'The changed setting is read');

        CommissionTestData.setSetting(new Map<String, Object>{ 'Target_Periods__c' => null });
        System.assertEquals(4, CommissionCatalog.targetPeriodOptions().size(), 'A blank setting offers every period');
        System.assertEquals(System.Label.Commission_Exceed_Mode_Marginal, CommissionCatalog.optionLabel(CommissionCatalog.exceedModeOptions(), 'Marginal'), 'The label of a stored value');
        System.assertEquals('Other', CommissionCatalog.optionLabel(CommissionCatalog.exceedModeOptions(), 'Other'), 'An unknown value is shown as it is');
    }

    @IsTest
    static void listOfSplitsTrimsAndLowers() {
        System.assertEquals(new Set<String>{ 'a', 'b', 'c d' }, CommissionCatalog.listOf(' A, b;  C d ;; '), 'Commas and semicolons separate, spaces and case are ignored');
        System.assertEquals(0, CommissionCatalog.listOf(null).size(), 'Nothing in, nothing out');
        System.assertEquals(0, CommissionCatalog.listOf('  ').size(), 'A blank text has no values');
    }

    @IsTest
    static void readsTheCustomMetadataWhenNothingIsInjected() {
        CommissionCatalog.testSetting = null;
        CommissionCatalog.testDesignations = null;
        CommissionCatalog.testTriggers = null;

        Commission_Setting__mdt setting = CommissionCatalog.setting();
        System.assertNotEquals(null, setting, 'A setting is always returned, blank when the record is missing');
        System.assert(setting === CommissionCatalog.setting(), 'The setting is read once per transaction');
        List<CommissionDto.Designation> designations = CommissionCatalog.designations();
        System.assertNotEquals(null, designations, 'Designations are read from the custom metadata');
        System.assertEquals(designations.size(), CommissionCatalog.designationByKey().size(), 'Every designation has its own key');
        List<CommissionDto.TriggerOption> events = CommissionCatalog.triggers();
        System.assertNotEquals(null, events, 'Payout events are read from the custom metadata');
        System.assertEquals(events.size(), CommissionCatalog.triggerByKey().size(), 'Every payout event has its own key');
        System.assertNotEquals(null, CommissionCatalog.forScreen().settings, 'The screen catalog is built from the real records too');
    }
}