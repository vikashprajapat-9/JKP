// The Edit popup of the Partner Portal Leads page (partnerWebPortalLeadEditController), run as a partner like the portal
// runs it: a channel partner moves their own lead through the stages of the Lead Nurturing chart with what goes with each
// stage (call log and lead details, all optional and including those of the stages before it; the JKP queue; a site visit
// request for the lead's project; the visit that took place), and what is refused: wrong values, an executive's lead for
// the channel head, and leads JKP owns, that wait for approval, are booked or went to another partner.
@isTest
private class partnerWebPortalLeadEditControllerTest {

    private static Integer leadCount = 0;

    // The stages of the chart, as the Partner Portal Lead Status records hold them
    private static void useStatuses() {
        partnerWebPortalLeadEditController.statusOverride = (List<Partner_Portal_Lead_Status__mdt>) JSON.deserialize(JSON.serialize(
            new List<Map<String, Object>>{
                status('Not Reachable', 1, 'Not Reachable', false, null, null, null),
                status('In-Discussion', 2, 'In Discussion', true, null, null, null),
                status('Not Interested', 3, 'Not Interested', false, 'Loss_Reason__c', 'Re_Marketing_Queue', null),
                status('Contacted', 4, 'Good Response', false,
                    'Purchase_Purpose__c, Unit_Type__c, Unit_Size__c, Purchase_Timeline__c, Assess_Budget__c, Assess_Finance_Readiness__c', null, null),
                status('Qualified', 5, null, false, 'Qualification_Status_Reason__c', null, null, 'Contacted'),
                status('Not Qualified', 6, null, false, 'Qualification_Status_Reason__c', null, null, 'Contacted'),
                status('Site Visit Scheduled', 7, null, false, null, null, 'Request', 'Contacted, Qualified'),
                status('Visited', 8, null, false, null, null, 'Complete', 'Contacted, Qualified')
            }), List<Partner_Portal_Lead_Status__mdt>.class);
    }

    // The JKP CP Executive (whose manager is the CP Manager) who approves site visit requests
    private static User cpExecutive() {
        Id adminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        User manager = internalUser(adminProfileId, 'lemgr', null);
        User executive;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert manager;
            executive = internalUser(adminProfileId, 'leexec', manager.Id);
            insert executive;
        }
        useVisitSetting(executive.Username);
        return executive;
    }

    // The visit settings of the Partner Portal Setting (the CP Executive: the given user)
    private static void useVisitSetting(String executiveUsername) {
        PartnerSiteVisitService.setting = new Partner_Portal_Setting__mdt(Visit_Status__c = 'Upcoming', Visit_Request_Status__c = 'Requested',
            Visit_Rejected_Status__c = 'Rejected', Open_Visit_Statuses__c = 'Upcoming', Completed_Visit_Status__c = 'Completed',
            Cancelled_Visit_Status__c = 'Cancelled', CP_Lead_Lost_Status__c = 'Site Visit Done by Other Agent',
            CP_Executive_Username__c = executiveUsername);
        PartnerSiteVisitService.stageByAction = new Map<String, String>{ 'request' => 'Site Visit Scheduled', 'complete' => 'Visited' };
    }

    private static User internalUser(Id profileId, String alias, Id managerId) {
        return new User(ProfileId = profileId, Alias = alias, LastName = 'Lead Edit ' + alias, Email = alias + '@example.com',
            Username = alias + '.' + UserInfo.getOrganizationId() + '@lead-edit-test.example.com', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', TimeZoneSidKey = 'Asia/Colombo', ManagerId = managerId);
    }

    private static Map<String, Object> status(String value, Integer order, String disposition, Boolean followUp, String fields, String queue,
            String visitAction) {
        return status(value, order, disposition, followUp, fields, queue, visitAction, null);
    }

    // A stage that also shows the Lead fields of the stages before it (Previous Stages)
    private static Map<String, Object> status(String value, Integer order, String disposition, Boolean followUp, String fields, String queue,
            String visitAction, String previousStages) {
        return new Map<String, Object>{
            'DeveloperName' => value.replaceAll('[^A-Za-z]', '_'), 'Lead_Status__c' => value, 'Order__c' => order,
            'Description__c' => value + ' stage', 'Call_Disposition__c' => disposition, 'Follow_Up_Required__c' => followUp,
            'Required_Lead_Fields__c' => fields, 'Owner_Queue__c' => queue, 'Visit_Action__c' => visitAction,
            'Previous_Stages__c' => previousStages
        };
    }

    private static Id accountOf(User portalUser) {
        return [SELECT Contact.AccountId FROM User WHERE Id = :portalUser.Id].Contact.AccountId;
    }

    // A channel partner lead of the account, owned by the given user
    private static Lead leadOf(Id channelPartnerId, Id ownerId, Id projectId) {
        leadCount++;
        Lead record = new Lead(LastName = 'Edit Buyer ' + leadCount, Company = 'Edit Buyer Holdings ' + leadCount,
            Phone = '07712388' + String.valueOf(leadCount).leftPad(2, '0'), Email = 'edit.buyer' + leadCount + '@example.com',
            LeadSource = 'Channel Partner', Budget_Aligned__c = 'Matching Budget', Project__c = projectId,
            Channel_Partner__c = channelPartnerId, OwnerId = ownerId);
        insert record;
        return record;
    }

    private static Id project() {
        Project__c project = TestRecordDefaults.project('Lead Edit Test Project', true);
        insert project;
        return project.Id;
    }

    // A call an hour ago, as the page sends it
    private static Map<String, Object> call(String subject) {
        return new Map<String, Object>{ 'callDateTime' => JSON.serialize(Datetime.now().addHours(-1)).remove('"'), 'subject' => subject,
            'description' => 'Spoke about the project' };
    }

    // The reason the change is refused, or null when it is saved
    private static String refusal(Id leadId, String status, Map<String, Object> values) {
        try {
            partnerWebPortalLeadEditController.saveStatus(leadId, status, values);
            return null;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    // A channel head moves their own lead through the call stages and the qualification stages. Each stage shows its own
    // Lead fields and those of the stages before it, all optional: a call without a follow-up, Contacted with five of its
    // six details and Qualified with only its reason all save, and an empty field never clears what the lead has. A lead
    // the partner owns gets no internal "Schedule a visit" task when it is Qualified.
    @isTest
    static void aPartnerMovesTheirLeadThroughTheStages() {
        useStatuses();
        User partner = PartnerPortalTestUser.create();
        Id projectId = project();
        Lead record = leadOf(accountOf(partner), partner.Id, projectId);

        partnerWebPortalLeadEditController.EditOptions options;
        Test.startTest();
        System.runAs(partner) {
            options = partnerWebPortalLeadEditController.getEditOptions(record.Id);
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'Not Reachable', call('Tried to call'));
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'In-Discussion', call('Discussed the units'));
            Map<String, Object> discussion = call('Discussed the units again');
            discussion.put('followUpDateTime', JSON.serialize(Datetime.now().addDays(1)).remove('"'));
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'In-Discussion', discussion);
            Map<String, Object> contacted = call('Qualified the requirement');
            contacted.putAll(new Map<String, Object>{ 'Purchase_Purpose__c' => 'Investment', 'Unit_Type__c' => '2 BR', 'Unit_Size__c' => '950',
                'Purchase_Timeline__c' => 'Within 3 Months', 'Assess_Budget__c' => 'Yes', 'Assess_Finance_Readiness__c' => '' });
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'Contacted', contacted);
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'Qualified', new Map<String, Object>{
                'Qualification_Status_Reason__c' => 'Budget and timeline confirmed', 'Purchase_Purpose__c' => '', 'Unit_Type__c' => '' });
        }
        Test.stopTest();

        System.assert(options.canEdit, options.readOnlyReason);
        System.assertEquals(8, options.statuses.size());
        System.assertEquals(0, options.statuses[0].fields.size(), 'Not Reachable has no Lead fields');
        System.assertEquals(6, options.statuses[3].fields.size(), 'Contacted shows the qualification fields');
        System.assertEquals('picklist', options.statuses[3].fields[0].type);
        System.assertEquals('number', options.statuses[3].fields[2].type, 'Unit Size');
        System.assertEquals(7, options.statuses[4].fields.size(), 'Qualified: the six of Contacted, then its reason');
        System.assertEquals('Purchase_Purpose__c', options.statuses[4].fields[0].apiName);
        System.assertEquals('Qualification_Status_Reason__c', options.statuses[4].fields[6].apiName);
        System.assertEquals(7, options.statuses[5].fields.size(), 'Not Qualified, the same');
        System.assertEquals(7, options.statuses[6].fields.size(), 'Site Visit Scheduled: Contacted and Qualified');
        System.assertEquals(7, options.statuses[7].fields.size(), 'Visited: Contacted and Qualified');
        System.assertEquals(true, options.statuses[1].followUpRequired, 'In-Discussion takes a follow-up');
        Lead saved = [SELECT Status, Purchase_Purpose__c, Unit_Type__c, Unit_Size__c, Assess_Finance_Readiness__c, Qualification_Status_Reason__c,
            Lead_Follow_Up_DateTime__c, OwnerId FROM Lead WHERE Id = :record.Id];
        System.assertEquals('Qualified', saved.Status);
        System.assertEquals('Investment', saved.Purchase_Purpose__c, 'Left empty at Qualified: kept');
        System.assertEquals('2 BR', saved.Unit_Type__c);
        System.assertEquals(950, saved.Unit_Size__c);
        System.assertEquals(null, saved.Assess_Finance_Readiness__c, 'Not given');
        System.assertEquals('Budget and timeline confirmed', saved.Qualification_Status_Reason__c);
        System.assertNotEquals(null, saved.Lead_Follow_Up_DateTime__c, 'The follow-up of the second In-Discussion call');
        System.assertEquals(partner.Id, saved.OwnerId, 'Still the partner\'s lead');
        List<Call_Disposition__c> calls = [SELECT Call_Disposition__c, Subject__c, Follow_Up_DateTime__c FROM Call_Disposition__c
            WHERE Lead__c = :record.Id ORDER BY CreatedDate, Name];
        System.assertEquals(4, calls.size(), 'A call log per call stage');
        System.assertEquals('Not Reachable', calls[0].Call_Disposition__c);
        System.assertEquals('In Discussion', calls[1].Call_Disposition__c);
        System.assertEquals(null, calls[1].Follow_Up_DateTime__c, 'No follow-up given: optional on the portal');
        System.assertNotEquals(null, calls[2].Follow_Up_DateTime__c);
        System.assertEquals('Good Response', calls[3].Call_Disposition__c);
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhoId = :record.Id AND Subject = 'Schedule a visit'],
            'No internal task for a lead the partner works on the portal');
    }

    // A call stage saves with nothing filled in, and then no call log is saved: nothing is filled in for the partner. A
    // call log filled in only in part keeps just what was given.
    @isTest
    static void aCallStageSavesWithoutACallLog() {
        useStatuses();
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Datetime followUp = Datetime.now().addDays(2);

        Test.startTest();
        System.runAs(partner) {
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'Not Reachable', new Map<String, Object>{ 'subject' => '  ', 'description' => '' });
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'In-Discussion', new Map<String, Object>{
                'followUpDateTime' => JSON.serialize(followUp).remove('"') });
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'Contacted', new Map<String, Object>{ 'description' => 'Spoke briefly' });
        }
        Test.stopTest();

        Lead saved = [SELECT Status, Lead_Follow_Up_DateTime__c FROM Lead WHERE Id = :record.Id];
        System.assertEquals('Contacted', saved.Status);
        List<Call_Disposition__c> calls = [SELECT Call_Disposition__c, Subject__c, Call_DateTime__c, Description__c, Follow_Up_DateTime__c
            FROM Call_Disposition__c WHERE Lead__c = :record.Id ORDER BY CreatedDate, Name];
        System.assertEquals(2, calls.size(), 'No call log for Not Reachable: nothing was filled in');
        System.assertEquals('In Discussion', calls[0].Call_Disposition__c);
        System.assertEquals(null, calls[0].Subject__c, 'Only what was given');
        System.assertEquals(null, calls[0].Call_DateTime__c);
        System.assertNotEquals(null, calls[0].Follow_Up_DateTime__c);
        System.assertEquals(calls[0].Follow_Up_DateTime__c, saved.Lead_Follow_Up_DateTime__c);
        System.assertEquals('Good Response', calls[1].Call_Disposition__c);
        System.assertEquals('Spoke briefly', calls[1].Description__c);
        System.assertEquals(null, calls[1].Subject__c);
    }

    // Not Interested saves without a Loss Reason (optional on the portal), or with Loss Reason Other and its details;
    // JKP's Re-Marketing Queue then takes the lead over, and the partner sees it read-only
    @isTest
    static void notInterestedHandsTheLeadToReMarketing() {
        useStatuses();
        User partner = PartnerPortalTestUser.create();
        Id projectId = project();
        Lead withoutReason = leadOf(accountOf(partner), partner.Id, projectId);
        Lead record = leadOf(accountOf(partner), partner.Id, projectId);

        partnerWebPortalLeadEditController.SaveResult bare;
        partnerWebPortalLeadEditController.SaveResult result;
        partnerWebPortalLeadEditController.EditOptions after;
        Test.startTest();
        System.runAs(partner) {
            bare = partnerWebPortalLeadEditController.saveStatus(withoutReason.Id, 'Not Interested', new Map<String, Object>());
            Map<String, Object> values = call('Not interested any more');
            values.put('Loss_Reason__c', 'Other');
            values.put('Other_Loss_Reason__c', 'Bought elsewhere');
            result = partnerWebPortalLeadEditController.saveStatus(record.Id, 'Not Interested', values);
            after = partnerWebPortalLeadEditController.getEditOptions(record.Id);
        }
        Test.stopTest();

        Id reMarketing = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Re_Marketing_Queue'].Id;
        System.assert(bare.handedToJkp);
        Lead savedBare = [SELECT Status, Loss_Reason__c, OwnerId FROM Lead WHERE Id = :withoutReason.Id];
        System.assertEquals('Not Interested', savedBare.Status);
        System.assertEquals(null, savedBare.Loss_Reason__c, 'Optional on the portal');
        System.assertEquals(reMarketing, savedBare.OwnerId);
        System.assertEquals(0, [SELECT COUNT() FROM Call_Disposition__c WHERE Lead__c = :withoutReason.Id], 'No call log filled in, none saved');
        System.assert(result.handedToJkp);
        Lead saved = [SELECT Status, Loss_Reason__c, Other_Loss_Reason__c, OwnerId FROM Lead WHERE Id = :record.Id];
        System.assertEquals('Not Interested', saved.Status);
        System.assertEquals('Other', saved.Loss_Reason__c);
        System.assertEquals('Bought elsewhere', saved.Other_Loss_Reason__c);
        System.assertEquals(reMarketing, saved.OwnerId);
        System.assertEquals('Not Interested', [SELECT Call_Disposition__c FROM Call_Disposition__c WHERE Lead__c = :record.Id].Call_Disposition__c);
        System.assert(!after.canEdit, 'Read-only once JKP owns it');
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_READ_ONLY_JKP, after.readOnlyReason);
    }

    // A channel head sees their executive's leads read-only, on the Leads page and in the popup
    @isTest
    static void aChannelHeadSeesTheirExecutivesLeadsReadOnly() {
        useStatuses();
        User head = PartnerPortalTestUser.create();
        Id headAccountId = accountOf(head);
        Account executive = new Account(Name = 'Edit Test Executive', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Channel_Head__c = headAccountId);
        insert executive;
        Id projectId = project();
        Lead own = leadOf(headAccountId, head.Id, projectId);
        Lead executives = leadOf(executive.Id, UserInfo.getUserId(), projectId);
        partnerWebPortalLeadController.setting = new Partner_Portal_Setting__mdt(Lead_Source__c = 'Channel Partner');

        partnerWebPortalLeadEditController.EditOptions options;
        String refused;
        partnerWebPortalLeadController.LeadsResponse page;
        Test.startTest();
        System.runAs(head) {
            options = partnerWebPortalLeadEditController.getEditOptions(executives.Id);
            refused = refusal(executives.Id, 'Not Reachable', call('Trying the executive\'s lead'));
            page = partnerWebPortalLeadController.getLeads(null, null, 1, 10);
        }
        Test.stopTest();

        System.assert(!options.canEdit);
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_READ_ONLY_TEAM, options.readOnlyReason);
        System.assertEquals(0, options.statuses.size(), 'No stages for a read-only lead');
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_READ_ONLY_TEAM, refused);
        Map<Id, partnerWebPortalLeadController.LeadRow> rows = new Map<Id, partnerWebPortalLeadController.LeadRow>();
        for (partnerWebPortalLeadController.LeadRow row : page.leads) {
            rows.put(row.leadId, row);
        }
        System.assertEquals(2, rows.size(), 'The head sees both');
        System.assert(rows.get(own.Id).canEdit, 'Their own lead');
        System.assert(!rows.get(executives.Id).canEdit, 'The executive\'s lead');
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_READ_ONLY_TEAM, rows.get(executives.Id).readOnlyReason);
    }

    // An executive updates their own lead
    @isTest
    static void anExecutiveUpdatesTheirOwnLead() {
        useStatuses();
        Id projectId = project();
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>{ projectId });
        Lead record = leadOf(accountOf(executive), executive.Id, projectId);

        Test.startTest();
        System.runAs(executive) {
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'Not Reachable', call('No answer'));
        }
        Test.stopTest();

        System.assertEquals('Not Reachable', [SELECT Status FROM Lead WHERE Id = :record.Id].Status);
    }

    // Wrong values (not missing ones: every detail is optional) and stages are refused with the reason, and nothing is
    // saved
    @isTest
    static void refusesWhatTheStageDoesNotAllow() {
        useStatuses();
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());

        Map<String, String> refusals = new Map<String, String>();
        Test.startTest();
        System.runAs(partner) {
            Map<String, Object> future = call('Tomorrow\'s call');
            future.put('callDateTime', JSON.serialize(Datetime.now().addDays(1)).remove('"'));
            refusals.put('future call', refusal(record.Id, 'Not Reachable', future));
            Map<String, Object> pastFollowUp = call('Discussed');
            pastFollowUp.put('followUpDateTime', JSON.serialize(Datetime.now().addDays(-1)).remove('"'));
            refusals.put('past follow-up', refusal(record.Id, 'In-Discussion', pastFollowUp));
            Map<String, Object> size = call('Qualified');
            size.putAll(new Map<String, Object>{ 'Purchase_Purpose__c' => 'Investment', 'Unit_Type__c' => '2 BR', 'Unit_Size__c' => '0',
                'Purchase_Timeline__c' => 'Within 3 Months', 'Assess_Budget__c' => 'Yes', 'Assess_Finance_Readiness__c' => 'Yes' });
            refusals.put('size 0', refusal(record.Id, 'Contacted', size));
            size.put('Unit_Size__c', '950');
            size.put('Purchase_Purpose__c', 'Not a purpose');
            refusals.put('unknown picklist value', refusal(record.Id, 'Contacted', size));
            refusals.put('unknown stage', refusal(record.Id, 'Converted', call('x')));
            refusals.put('visit without details', refusal(record.Id, 'Site Visit Scheduled', new Map<String, Object>()));
            refusals.put('visited without visit', refusal(record.Id, 'Visited', new Map<String, Object>()));
            refusals.put('no stage', refusal(record.Id, null, null));
        }
        Test.stopTest();

        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_EDIT_CALL_IN_FUTURE, refusals.get('future call'));
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_EDIT_FOLLOW_UP_PAST, refusals.get('past follow-up'));
        System.assertEquals(String.format(partnerWebPortalLeadEditController.PARTNER_LEAD_EDIT_NUMBER_INVALID, new List<Object>{
            Lead.Unit_Size__c.getDescribe().getLabel() }), refusals.get('size 0'));
        System.assertEquals(String.format(partnerWebPortalLeadEditController.PARTNER_LEAD_EDIT_FIELD_REQUIRED, new List<Object>{
            Lead.Purchase_Purpose__c.getDescribe().getLabel() }), refusals.get('unknown picklist value'));
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_EDIT_STATUS_UNKNOWN, refusals.get('unknown stage'));
        System.assertEquals(String.format(partnerWebPortalLeadEditController.PARTNER_LEAD_EDIT_FIELD_REQUIRED, new List<Object>{
            Visit__c.Project__c.getDescribe().getLabel() }), refusals.get('visit without details'));
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_VISIT_CHOOSE_VISIT, refusals.get('visited without visit'));
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_EDIT_STATUS_UNKNOWN, refusals.get('no stage'));
        System.assertEquals(0, [SELECT COUNT() FROM Call_Disposition__c], 'Nothing saved');
        System.assertEquals(0, [SELECT COUNT() FROM Visit__c], 'No visit requested');
        System.assertEquals('Assigned', [SELECT Status FROM Lead WHERE Id = :record.Id].Status);
    }

    // Site Visit Scheduled sends a site visit request, and the lead moves there once the JKP CP Executive approves it;
    // Visited marks the scheduled visit completed. While the request waits, Site Visit Scheduled cannot be chosen again,
    // and without a scheduled visit Visited cannot be chosen.
    @isTest
    static void aPartnerRequestsAVisitAndMarksItVisited() {
        useStatuses();
        User executive = cpExecutive();
        User partner = PartnerPortalTestUser.create();
        Id projectId = project();
        Lead record = leadOf(accountOf(partner), partner.Id, projectId);
        String type = PartnerSiteVisitService.requirementTypes()[0].get('value');

        partnerWebPortalLeadEditController.EditOptions before;
        partnerWebPortalLeadEditController.SaveResult requested;
        partnerWebPortalLeadEditController.EditOptions waiting;
        System.runAs(partner) {
            before = partnerWebPortalLeadEditController.getEditOptions(record.Id);
            requested = partnerWebPortalLeadEditController.saveStatus(record.Id, 'Site Visit Scheduled', new Map<String, Object>{
                'visitProjectId' => projectId, 'visitRequirementType' => type, 'visitDate' => String.valueOf(Date.today()),
                'visitTime' => '23:59', 'visitDescription' => ' Couple, 2 BR ', 'Unit_Type__c' => '2 BR', 'Purchase_Purpose__c' => '' });
            waiting = partnerWebPortalLeadEditController.getEditOptions(record.Id);
        }
        Visit__c visit = [SELECT Id, Status__c, Approval_Status__c, Project__c, Requirement_Type__c, Visit_Date__c, Visit_Time__c, Visit_Description__c
            FROM Visit__c WHERE Lead__c = :record.Id];
        String stageWhileWaiting = [SELECT Status FROM Lead WHERE Id = :record.Id].Status;
        Id workItemId = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :visit.Id].Id;
        Test.startTest();
        System.runAs(executive) {
            Approval.ProcessWorkitemRequest decision = new Approval.ProcessWorkitemRequest();
            decision.setWorkitemId(workItemId);
            decision.setAction('Approve');
            Approval.process(decision);
        }
        Test.stopTest();
        // The visit's time has come
        update new Visit__c(Id = visit.Id, Visit_Time__c = Time.newInstance(0, 0, 0, 0));
        partnerWebPortalLeadEditController.EditOptions scheduled;
        partnerWebPortalLeadEditController.SaveResult visited;
        System.runAs(partner) {
            scheduled = partnerWebPortalLeadEditController.getEditOptions(record.Id);
            visited = partnerWebPortalLeadEditController.saveStatus(record.Id, 'Visited', new Map<String, Object>{ 'visitId' => visit.Id });
        }

        System.assertNotEquals(null, before.visit, 'The site visit choices');
        System.assertEquals(String.valueOf(projectId), before.visit.projectId, 'The lead\'s project');
        System.assertEquals('Lead Edit Test Project', before.visit.projectName, 'Shown read-only');
        System.assertEquals(true, before.visit.projectFromLead);
        System.assertEquals(0, before.visit.projects.size(), 'No other project to choose');
        System.assertEquals(String.valueOf(Date.today()), before.visit.today);
        System.assertEquals(null, before.statuses[6].unavailableReason, 'A visit can be requested');
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_VISIT_NONE_TO_COMPLETE, before.statuses[7].unavailableReason, 'Nothing scheduled to complete yet');

        System.assertEquals(true, requested.visitRequested);
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_VISIT_REQUESTED, requested.message);
        System.assertEquals('Assigned', stageWhileWaiting, 'The stage moves once the request is approved');
        System.assertEquals('Requested', visit.Status__c);
        System.assertEquals(PartnerSiteVisitService.PENDING_EXECUTIVE, visit.Approval_Status__c);
        System.assertEquals(projectId, visit.Project__c);
        System.assertEquals(type, visit.Requirement_Type__c);
        System.assertEquals(Date.today(), visit.Visit_Date__c);
        System.assertEquals(Time.newInstance(23, 59, 0, 0), visit.Visit_Time__c);
        System.assertEquals('Couple, 2 BR', visit.Visit_Description__c);
        System.assertEquals(7, before.statuses[6].fields.size(), 'The details of Contacted and Qualified, optional');
        System.assertEquals('2 BR', [SELECT Unit_Type__c FROM Lead WHERE Id = :record.Id].Unit_Type__c, 'Saved with the request');
        System.assertEquals('A site visit request for this lead is already waiting for approval.', waiting.statuses[6].unavailableReason);

        System.assertEquals('Site Visit Scheduled', scheduled.currentStatus, 'Approved');
        System.assertEquals(1, scheduled.visit.scheduled.size());
        System.assertEquals(true, scheduled.visit.scheduled[0].canComplete, 'Today\'s visit');
        System.assertEquals(null, scheduled.statuses[7].unavailableReason);
        System.assertEquals('Visited', visited.status);
        System.assertEquals('Visited', [SELECT Status FROM Lead WHERE Id = :record.Id].Status);
        System.assertEquals('Completed', [SELECT Status__c FROM Visit__c WHERE Id = :visit.Id].Status__c);
    }

    // A site visit request is for the lead's project: another project is refused, and a lead whose project is no longer
    // open for site visits (not active) cannot request one: Site Visit Scheduled says why, and so does saving
    @isTest
    static void aVisitIsForTheLeadsProject() {
        useStatuses();
        useVisitSetting(null);
        User partner = PartnerPortalTestUser.create();
        Id projectId = project();
        Project__c closing = TestRecordDefaults.project('Closed Edit Project', true);
        insert closing;
        Lead record = leadOf(accountOf(partner), partner.Id, projectId);
        Lead closedLead = leadOf(accountOf(partner), partner.Id, closing.Id);
        update new Project__c(Id = closing.Id, Active__c = false);
        String type = PartnerSiteVisitService.requirementTypes()[0].get('value');

        String anotherProject;
        partnerWebPortalLeadEditController.EditOptions closedOptions;
        String closedRequest;
        Test.startTest();
        System.runAs(partner) {
            anotherProject = refusal(record.Id, 'Site Visit Scheduled', visitValues(closing.Id, type));
            closedOptions = partnerWebPortalLeadEditController.getEditOptions(closedLead.Id);
            closedRequest = refusal(closedLead.Id, 'Site Visit Scheduled', visitValues(closing.Id, type));
        }
        Test.stopTest();

        String notOpen = String.format('Site visits cannot be requested for this lead now: its project, {0}, is not open for site visits. Please contact your CP Executive.', new List<Object>{ 'Closed Edit Project' });
        System.assertEquals(String.format('A site visit for this lead can only be for its project, {0}. Please reload the page and try again.', new List<Object>{ 'Lead Edit Test Project' }), anotherProject);
        System.assertEquals(notOpen, closedOptions.statuses[6].unavailableReason, 'Site Visit Scheduled says why it cannot be chosen');
        System.assertEquals(String.valueOf(closing.Id), closedOptions.visit.projectId, 'Still the lead\'s project');
        System.assertEquals('Closed Edit Project', closedOptions.visit.projectName);
        System.assertEquals(notOpen, closedRequest, 'Instead of "Project is required"');
        System.assertEquals(0, [SELECT COUNT() FROM Visit__c], 'No visit requested');
    }

    // A site visit request as the popup sends it: tomorrow, late in the evening
    private static Map<String, Object> visitValues(Id projectId, String type) {
        return new Map<String, Object>{ 'visitProjectId' => projectId, 'visitRequirementType' => type,
            'visitDate' => String.valueOf(Date.today().addDays(1)), 'visitTime' => '23:59', 'visitDescription' => 'Couple, 2 BR' };
    }

    // A call stage can be chosen again while the lead is at it, to log another call; a stage without a call cannot
    @isTest
    static void anotherCallCanBeLoggedAtTheSameStage() {
        useStatuses();
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());

        partnerWebPortalLeadEditController.EditOptions atNotReachable;
        partnerWebPortalLeadEditController.EditOptions atQualified;
        Test.startTest();
        System.runAs(partner) {
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'Not Reachable', call('First try'));
            atNotReachable = partnerWebPortalLeadEditController.getEditOptions(record.Id);
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'Not Reachable', call('Second try'));
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'Qualified',
                new Map<String, Object>{ 'Qualification_Status_Reason__c' => 'Ready to buy' });
            atQualified = partnerWebPortalLeadEditController.getEditOptions(record.Id);
        }
        Test.stopTest();

        System.assert(atNotReachable.statuses[0].current && atNotReachable.statuses[0].repeatable, 'Not Reachable again');
        System.assertEquals(2, [SELECT COUNT() FROM Call_Disposition__c WHERE Lead__c = :record.Id AND Call_Disposition__c = 'Not Reachable']);
        System.assert(atQualified.statuses[4].current, 'Qualified is current');
        System.assertEquals(false, atQualified.statuses[4].repeatable, 'No call to log at Qualified');
        System.assertEquals(false, atQualified.statuses[2].repeatable, 'Not Interested hands the lead over');
        System.assertEquals(true, atQualified.statuses[6].repeatable, 'Another site visit');
    }

    // Not Interested hands the lead to JKP: its scheduled visits are cancelled
    @isTest
    static void notInterestedCancelsTheScheduledVisits() {
        useStatuses();
        useVisitSetting(null);
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, project());
        Visit__c scheduled = new Visit__c(Lead__c = record.Id, Status__c = 'Upcoming', Visit_Date__c = Date.today().addDays(2), OwnerId = partner.Id);
        // An earlier visit JKP replaced (a completed one would hand the lead over to JKP)
        Visit__c done = new Visit__c(Lead__c = record.Id, Status__c = 'Rescheduled', Visit_Date__c = Date.today().addDays(-2), OwnerId = partner.Id);
        insert new List<Visit__c>{ scheduled, done };

        Map<String, Object> values = call('Not interested any more');
        values.put('Loss_Reason__c', 'Other');
        values.put('Other_Loss_Reason__c', 'Bought elsewhere');
        Test.startTest();
        System.runAs(partner) {
            partnerWebPortalLeadEditController.saveStatus(record.Id, 'Not Interested', values);
        }
        Test.stopTest();

        Visit__c cancelled = [SELECT Status__c, Reason_of_Cancellation__c FROM Visit__c WHERE Id = :scheduled.Id];
        System.assertEquals('Cancelled', cancelled.Status__c);
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_VISIT_NOT_INTERESTED_REASON, cancelled.Reason_of_Cancellation__c);
        System.assertEquals('Rescheduled', [SELECT Status__c FROM Visit__c WHERE Id = :done.Id].Status__c, 'A past visit stays');
    }

    // Booked leads, leads waiting for approval, leads another partner won, leads JKP owns, and users without a partner
    // account cannot be edited, each with its reason
    @isTest
    static void readOnlyLeadsSayWhy() {
        useStatuses();
        User partner = PartnerPortalTestUser.create();
        Id accountId = accountOf(partner);
        Id projectId = project();
        Lead waiting = leadOf(accountId, partner.Id, projectId);
        Lead lost = leadOf(accountId, partner.Id, projectId);
        Lead jkps = leadOf(accountId, partner.Id, projectId);
        // A JKP user took the lead (for example from the Re-Marketing Queue)
        Lead takenByJkp = leadOf(accountId, UserInfo.getUserId(), projectId);
        update new List<Lead>{
            new Lead(Id = waiting.Id, CP_Approval_Status__c = 'Pending'),
            new Lead(Id = lost.Id, Status = 'Site Visit Done by Other Agent'),
            new Lead(Id = jkps.Id, OwnerId = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Re_Marketing_Queue'].Id)
        };
        Lead booked = leadOf(accountId, UserInfo.getUserId(), projectId);
        Database.LeadConvert conversion = new Database.LeadConvert();
        conversion.setLeadId(booked.Id);
        conversion.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        Database.convertLead(conversion);

        Map<String, String> reasons = new Map<String, String>();
        Test.startTest();
        System.runAs(partner) {
            reasons.put('waiting', partnerWebPortalLeadEditController.getEditOptions(waiting.Id).readOnlyReason);
            reasons.put('lost', partnerWebPortalLeadEditController.getEditOptions(lost.Id).readOnlyReason);
            reasons.put('jkp', partnerWebPortalLeadEditController.getEditOptions(jkps.Id).readOnlyReason);
            reasons.put('taken by JKP', partnerWebPortalLeadEditController.getEditOptions(takenByJkp.Id).readOnlyReason);
            reasons.put('booked', partnerWebPortalLeadEditController.getEditOptions(booked.Id).readOnlyReason);
        }
        String internal;
        try {
            partnerWebPortalLeadEditController.getEditOptions(waiting.Id);
        } catch (AuraHandledException e) {
            internal = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_READ_ONLY_WAITING, reasons.get('waiting'));
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_READ_ONLY_LOST, reasons.get('lost'));
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_READ_ONLY_JKP, reasons.get('jkp'));
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_READ_ONLY_JKP, reasons.get('taken by JKP'), 'An internal user owns it');
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_LEAD_READ_ONLY_BOOKED, reasons.get('booked'));
        System.assertEquals(partnerWebPortalLeadEditController.PARTNER_PORTAL_NO_ACCESS, internal, 'An internal user has no partner account');
    }
}