@isTest
private class partnerWebPortalLeadControllerTest {

    // Answers the OneDrive token request and refuses the folder, so the folder job of the test project ends quietly
    private class OneDriveMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/oauth2/')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"test-token"}');
            } else {
                res.setStatusCode(503);
                res.setBody('{"error":{"code":"serviceNotAvailable"}}');
            }
            return res;
        }
    }

    // A partner, their executive, another team's partner and an active project
    private class Team {
        User partner;
        Id partnerAccountId;
        Account executive;
        Account outsider;
        Id projectId;
    }

    private static Integer leadCount = 0;

    // The org's filter chips, but Lost on Cancelled: the org's Closed Lost is an inactive stage that cannot be set
    private static void useSettings() {
        List<Map<String, Object>> filters = new List<Map<String, Object>>{
            new Map<String, Object>{ 'DeveloperName' => 'All', 'MasterLabel' => 'All', 'Order__c' => 1 },
            new Map<String, Object>{ 'DeveloperName' => 'Scheduled', 'MasterLabel' => 'Scheduled', 'Order__c' => 2,
                'Lead_Statuses__c' => 'Site Visit Scheduled' },
            new Map<String, Object>{ 'DeveloperName' => 'Active_Nurturing', 'MasterLabel' => 'Active/Nurturing', 'Order__c' => 3,
                'Lead_Statuses__c' => 'Assigned, In-Discussion, Contacted, Qualified' },
            new Map<String, Object>{ 'DeveloperName' => 'Visited', 'MasterLabel' => 'Visited', 'Order__c' => 4, 'Lead_Statuses__c' => 'Visited' },
            new Map<String, Object>{ 'DeveloperName' => 'Booked', 'MasterLabel' => 'Booked', 'Order__c' => 5, 'Booked__c' => true },
            new Map<String, Object>{ 'DeveloperName' => 'Lost', 'MasterLabel' => 'Lost', 'Order__c' => 6, 'Opportunity_Stages__c' => 'Cancelled' }
        };
        partnerWebPortalLeadController.filterOverride = (List<Partner_Portal_Lead_Filter__mdt>) JSON.deserialize(
            JSON.serialize(filters), List<Partner_Portal_Lead_Filter__mdt>.class);
        partnerWebPortalMyTeamController.setting = new Partner_Portal_Setting__mdt(
            Bookings_After_Stage__c = 'SPA Signing', Stages_Not_Counted_As_Bookings__c = 'Cancelled');
        partnerWebPortalLeadController.setting = new Partner_Portal_Setting__mdt(Lead_Source__c = 'Channel Partner');
    }

    private static Team newTeam() {
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        Team team = new Team();
        team.partner = PartnerPortalTestUser.create();
        team.partnerAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :team.partner.Id].Contact.AccountId;
        Id channelPartnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        team.executive = new Account(Name = 'Amal Perera', RecordTypeId = channelPartnerType, Channel_Head__c = team.partnerAccountId);
        team.outsider = new Account(Name = 'Other Partner', RecordTypeId = channelPartnerType);
        insert new List<Account>{ team.executive, team.outsider };
        Project__c project = TestRecordDefaults.project('Leads Test Project', true);
        insert project;
        team.projectId = project.Id;
        return team;
    }

    // A lead the lead validation rules accept, each with its own phone number
    private static Lead newLead(String name, String status, Id channelPartnerId, Id projectId) {
        leadCount++;
        return new Lead(LastName = name, Company = name + ' Holdings', Status = status, Phone = '07712340' + String.valueOf(leadCount).leftPad(2, '0'),
            Email = 'buyer' + leadCount + '@example.com', LeadSource = 'Channel Partner', Budget_Aligned__c = 'Matching Budget',
            Project__c = projectId, Channel_Partner__c = channelPartnerId);
    }

    // Converts the lead and moves its opportunity to the stage
    private static void convert(Lead converted, String stage) {
        Database.LeadConvert conversion = new Database.LeadConvert();
        conversion.setLeadId(converted.Id);
        conversion.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        Database.LeadConvertResult result = Database.convertLead(conversion);
        update new Opportunity(Id = result.getOpportunityId(), StageName = stage);
    }

    // The partner's four leads, their executive's four (two converted) and another team's lead that never shows
    private static Map<String, Lead> leadsOf(Team team) {
        Map<String, Lead> leads = new Map<String, Lead>{
            'scheduled' => newLead('Scheduled Buyer', 'Site Visit Scheduled', team.partnerAccountId, team.projectId),
            'assigned' => newLead('Assigned Buyer', 'Assigned', team.partnerAccountId, team.projectId),
            'visited' => newLead('Visited Buyer', 'Visited', team.partnerAccountId, team.projectId),
            'new' => newLead('New Buyer', 'New', team.partnerAccountId, team.projectId),
            'discussion' => newLead('Discussion Buyer', 'In-Discussion', team.executive.Id, team.projectId),
            'contacted' => newLead('Contacted Buyer', 'Contacted', team.executive.Id, team.projectId),
            'booked' => newLead('Booked Buyer', 'Qualified', team.executive.Id, team.projectId),
            'lost' => newLead('Lost Buyer', 'Qualified', team.executive.Id, team.projectId),
            'outsider' => newLead('Outsider Buyer', 'Assigned', team.outsider.Id, team.projectId)
        };
        insert leads.values();
        convert(leads.get('booked'), 'Tranche Payment');
        convert(leads.get('lost'), 'Cancelled');
        return leads;
    }

    private static Set<String> namesOf(partnerWebPortalLeadController.LeadsResponse response) {
        Set<String> names = new Set<String>();
        for (partnerWebPortalLeadController.LeadRow row : response.leads) {
            names.add(row.leadName);
        }
        return names;
    }

    @isTest
    static void eachFilterShowsItsShareOfTheTeamsLeads() {
        useSettings();
        Team team = newTeam();
        leadsOf(team);

        Map<String, Set<String>> shown = new Map<String, Set<String>>();
        List<String> chips = new List<String>();
        System.runAs(team.partner) {
            for (partnerWebPortalLeadController.LeadFilter filter : partnerWebPortalLeadController.getLeadFilters()) {
                chips.add(filter.label);
                shown.put(filter.key, namesOf(partnerWebPortalLeadController.getLeads(filter.key, '', 1, 50)));
            }
        }

        System.assertEquals(new List<String>{ 'All', 'Scheduled', 'Active/Nurturing', 'Visited', 'Booked', 'Lost' }, chips);
        System.assertEquals(new Set<String>{ 'Scheduled Buyer', 'Assigned Buyer', 'Visited Buyer', 'New Buyer', 'Discussion Buyer',
            'Contacted Buyer', 'Booked Buyer', 'Lost Buyer' }, shown.get('All'), 'The partner\'s and their executive\'s leads, not another team\'s');
        System.assertEquals(new Set<String>{ 'Scheduled Buyer' }, shown.get('Scheduled'));
        System.assertEquals(new Set<String>{ 'Assigned Buyer', 'New Buyer', 'Discussion Buyer', 'Contacted Buyer' }, shown.get('Active_Nurturing'),
            'A new channel partner lead moves to Assigned (the lead process)');
        System.assertEquals(new Set<String>{ 'Visited Buyer' }, shown.get('Visited'));
        System.assertEquals(new Set<String>{ 'Booked Buyer' }, shown.get('Booked'), 'Converted and past SPA Signing');
        System.assertEquals(new Set<String>{ 'Lost Buyer' }, shown.get('Lost'), 'Converted and in a lost stage');
    }

    @isTest
    static void rowsShowWhoseLeadItIsAndPageThroughTheTeam() {
        useSettings();
        Team team = newTeam();
        Map<String, Lead> leads = leadsOf(team);

        partnerWebPortalLeadController.LeadsResponse firstPage;
        partnerWebPortalLeadController.LeadsResponse lastPage;
        partnerWebPortalLeadController.LeadsResponse all;
        System.runAs(team.partner) {
            firstPage = partnerWebPortalLeadController.getLeads('All', null, 1, 3);
            lastPage = partnerWebPortalLeadController.getLeads('All', null, 3, 3);
            all = partnerWebPortalLeadController.getLeads(null, null, null, null);
        }

        System.assertEquals(8, firstPage.totalRecords);
        System.assertEquals(3, firstPage.totalPages);
        System.assertEquals(3, firstPage.leads.size());
        System.assertEquals(1, firstPage.leads[0].rowNo);
        System.assertEquals(2, lastPage.leads.size());
        System.assertEquals(7, lastPage.leads[0].rowNo);
        System.assertEquals(8, all.totalRecords, 'No filter shows the whole team');
        System.assertEquals(10, all.pageSize);

        for (partnerWebPortalLeadController.LeadRow row : all.leads) {
            if (row.leadName == 'Discussion Buyer') {
                System.assertEquals(leads.get('discussion').Id, row.leadNo);
                System.assertEquals('Amal Perera', row.partner, 'The executive whose lead it is');
                System.assertEquals('Leads Test Project', row.project, 'The project the lead is for');
                System.assertEquals(leads.get('discussion').Phone, row.mobile);
                System.assertEquals('In-Discussion', row.stage);
                System.assertEquals(Datetime.now().format('dd MMM yyyy'), row.createdDate);
            }
        }
    }

    @isTest
    static void searchFindsLeadsByWhatTheTableShows() {
        useSettings();
        Team team = newTeam();
        Map<String, Lead> leads = leadsOf(team);
        String phone = leads.get('visited').Phone;
        String spacedPhone = phone.left(3) + ' ' + phone.mid(3, 4) + '-' + phone.substring(7);

        Map<String, Set<String>> found = new Map<String, Set<String>>();
        System.runAs(team.partner) {
            for (String term : new List<String>{ 'discussion', 'amal', spacedPhone, String.valueOf(leads.get('new').Id), 'visited buyer holdings',
                    'Outsider', '%', 'In-Disc' }) {
                found.put(term, namesOf(partnerWebPortalLeadController.getLeads('All', term, 1, 50)));
            }
            found.put('Buyer in Scheduled', namesOf(partnerWebPortalLeadController.getLeads('Scheduled', 'Buyer', 1, 50)));
        }

        System.assertEquals(new Set<String>{ 'Discussion Buyer' }, found.get('discussion'), 'By lead name, in any capitals');
        System.assertEquals(new Set<String>{ 'Discussion Buyer', 'Contacted Buyer', 'Booked Buyer', 'Lost Buyer' }, found.get('amal'),
            'By the channel partner who brought the lead');
        System.assertEquals(new Set<String>{ 'Visited Buyer' }, found.get(spacedPhone), 'By mobile number, typed with spaces or dashes');
        System.assertEquals(new Set<String>{ 'New Buyer' }, found.get(String.valueOf(leads.get('new').Id)), 'By Lead No.');
        System.assertEquals(new Set<String>{ 'Visited Buyer' }, found.get('visited buyer holdings'), 'By company');
        System.assertEquals(new Set<String>{ 'Discussion Buyer' }, found.get('In-Disc'), 'By stage');
        System.assertEquals(new Set<String>(), found.get('Outsider'), 'Never another team\'s leads');
        System.assertEquals(new Set<String>(), found.get('%'), '% is searched for, not a wildcard');
        System.assertEquals(new Set<String>{ 'Scheduled Buyer' }, found.get('Buyer in Scheduled'), 'Search stays within the chosen filter');
    }

    // The same customer (and mobile number) can be a lead in more than one project: the Project Name column tells the
    // rows apart, in the table, in the search and in the export
    @isTest
    static void theProjectTellsApartLeadsOfTheSameCustomer() {
        useSettings();
        Team team = newTeam();
        Project__c tower = TestRecordDefaults.project('Harbour Tower Project', true);
        insert tower;
        // Told apart by more than the project where the org's own lead duplicate rules look, so that only the phone is shared
        Lead first = newLead('Twin Buyer', 'Assigned', team.partnerAccountId, team.projectId);
        insert first;
        Lead second = newLead('Twin Buyer Again', 'Assigned', team.partnerAccountId, tower.Id);
        second.Phone = first.Phone;
        insert second;

        partnerWebPortalLeadController.LeadsResponse byPhone;
        Set<Id> byProject = new Set<Id>();
        String csv;
        System.runAs(team.partner) {
            byPhone = partnerWebPortalLeadController.getLeads('All', first.Phone, 1, 50);
            for (partnerWebPortalLeadController.LeadRow row : partnerWebPortalLeadController.getLeads('All', 'harbour tower', 1, 50).leads) {
                byProject.add(row.leadId);
            }
            csv = partnerWebPortalLeadController.exportCSV('All', first.Phone);
        }

        Map<Id, String> projects = new Map<Id, String>();
        for (partnerWebPortalLeadController.LeadRow row : byPhone.leads) {
            System.assertEquals(first.Phone, row.mobile);
            projects.put(row.leadId, row.project);
        }
        System.assertEquals(new Map<Id, String>{ first.Id => 'Leads Test Project', second.Id => 'Harbour Tower Project' }, projects,
            'Two rows with the same mobile number, each with its project');
        System.assertEquals(new Set<Id>{ second.Id }, byProject, 'The search finds leads by their project');
        System.assert(csv.contains('"Leads Test Project","' + first.Phone + '"') && csv.contains('"Harbour Tower Project","' + first.Phone + '"'),
            'The export has the project of each row: ' + csv);
    }

    @isTest
    static void exportsTheChosenFilterForExcel() {
        useSettings();
        Team team = newTeam();
        leadsOf(team);
        insert new List<Lead>{
            newLead('Perera, "Sam"', 'Assigned', team.partnerAccountId, team.projectId),
            newLead('=HYPERLINK("x")', 'Contacted', team.executive.Id, team.projectId)
        };

        String csv;
        String searched;
        System.runAs(team.partner) {
            csv = partnerWebPortalLeadController.exportCSV('Active_Nurturing', '');
            searched = partnerWebPortalLeadController.exportCSV('Active_Nurturing', 'Sam');
        }

        List<String> lines = csv.split('\r\n');
        System.assertEquals('"Sr.","Lead Created Date","Lead No.","Lead Name","Channel Partner/Company Name","Project Name","Lead Mobile No.","Lead Stage"',
            lines[0]);
        System.assert(lines[1].contains('","Leads Test Project","0771234'), 'The project comes before the mobile number: ' + lines[1]);
        System.assertEquals(7, lines.size(), 'The header and the six Active/Nurturing leads (New Buyer is Assigned): ' + csv);
        System.assert(csv.contains('"Perera, ""Sam"""'), 'Commas and quotes stay inside their cell');
        System.assert(csv.contains('"\'=HYPERLINK(""x"")"'), 'A formula is exported as text');
        System.assert(!csv.contains('Visited Buyer') && !csv.contains('Outsider Buyer'), 'Only the chosen filter of the partner\'s team');
        System.assertEquals(2, searched.split('\r\n').size(), 'The search applies to the export too: ' + searched);
    }

    @isTest
    static void aUserWithoutAPartnerAccountHasNoLeads() {
        useSettings();
        Team team = newTeam();
        leadsOf(team);

        partnerWebPortalLeadController.LeadsResponse response = partnerWebPortalLeadController.getLeads('All', '', 1, 10);

        System.assertEquals(0, response.totalRecords);
        System.assertEquals(0, response.leads.size());
        System.assertEquals(1, partnerWebPortalLeadController.exportCSV('All', '').split('\r\n').size(), 'Only the header');
    }

    @isTest
    static void createsTheLeadForThePartnersTeam() {
        useSettings();
        Team team = newTeam();

        partnerWebPortalLeadController.CreateLeadResult result;
        partnerWebPortalLeadController.LeadsResponse listed;
        System.runAs(team.partner) {
            result = partnerWebPortalLeadController.createLead(' Kamal Perera ', '', ' kamal@example.com ', ' 0771239999 ', 'No. 42, Galle Road',
                team.projectId, 'Matching Budget', 'Prefers a sea view');
            listed = partnerWebPortalLeadController.getLeads('All', '', 1, 10);
        }

        System.assertEquals(LeadLogicController.CP_CREATED, result.outcome, 'Not a duplicate');
        Lead created = [SELECT LastName, Company, LeadSource, Email, Phone, Street, OwnerId, Channel_Partner__c, Project__c, Budget_Aligned__c,
            Description, Status FROM Lead WHERE Id = :result.leadId];
        System.assertEquals('Assigned', created.Status, 'A new channel partner lead moves to Assigned');
        System.assertEquals(team.partnerAccountId, created.Channel_Partner__c, 'The logged-in partner is the Channel Partner');
        System.assertEquals('Channel Partner', created.LeadSource, 'From the Partner Portal Setting');
        System.assertEquals('Kamal Perera', created.LastName);
        System.assertEquals('Individual', created.Company);
        System.assertEquals('kamal@example.com', created.Email);
        System.assertEquals('0771239999', created.Phone);
        System.assertEquals('No. 42, Galle Road', created.Street);
        System.assertEquals(team.partner.Id, created.OwnerId);
        System.assertEquals(team.projectId, created.Project__c);
        System.assertEquals('Matching Budget', created.Budget_Aligned__c);
        System.assertEquals('Prefers a sea view', created.Description);
        System.assertEquals(1, listed.totalRecords, 'The new lead is on the partner\'s Leads page');
    }

    @isTest
    static void refusesLeadsThatBreakTheRules() {
        useSettings();
        Team team = newTeam();
        Lead existing = newLead('Existing Buyer', 'New', team.partnerAccountId, team.projectId);
        insert existing;

        List<String> errors = new List<String>();
        System.runAs(team.partner) {
            for (List<String> details : new List<List<String>>{
                    new List<String>{ ' ', '0771230000', 'kamal@example.com', team.projectId, 'Matching Budget' },
                    new List<String>{ 'Kamal Perera', ' ', 'kamal@example.com', team.projectId, 'Matching Budget' },
                    new List<String>{ 'Kamal Perera', '0771230000', ' ', team.projectId, 'Matching Budget' },
                    new List<String>{ 'Kamal Perera', '0771230000', 'kamal@example.com', '', 'Matching Budget' },
                    new List<String>{ 'Kamal Perera', '0771230000', 'kamal@example.com', team.projectId, '' },
                    new List<String>{ 'Kamal Perera', existing.Phone, 'kamal@example.com', team.projectId, 'Matching Budget' },
                    new List<String>{ 'Kamal Perera', '12345', 'kamal@example.com', team.projectId, 'Matching Budget' } }) {
                try {
                    partnerWebPortalLeadController.createLead(details[0], null, details[2], details[1], null, details[3], details[4], null);
                    errors.add(null);
                } catch (AuraHandledException e) {
                    errors.add(e.getMessage());
                }
            }
        }

        System.assertEquals('Full Name is required', errors[0]);
        System.assertEquals('Mobile Number is required', errors[1]);
        System.assertEquals('Email ID is required', errors[2], 'Email ID is mandatory in the lead process');
        System.assertEquals('Please select an Interested Project', errors[3]);
        System.assertEquals('Please select a valid Budget Aligned', errors[4]);
        System.assertEquals(Label.CP_Lead_Already_Submitted, errors[5], 'The same customer from the same CP for the same project');
        System.assertEquals(Label.CP_Lead_Phone_Invalid, errors[6], 'A Mobile Number holds 9 to 15 digits');
        System.assertEquals(1, [SELECT COUNT() FROM Lead], 'Nothing new is saved');
    }

    // A partner whose portal access ended (Access Denied or Terminated) cannot add leads, should they reach the page
    // some other way than the login page
    @isTest
    static void aPartnerWithoutAccessCannotAddLeads() {
        useSettings();
        Team team = newTeam();
        update new Account(Id = team.partnerAccountId, Partner_Type__c = 'Access Denied');

        String refused;
        System.runAs(team.partner) {
            try {
                partnerWebPortalLeadController.createLead('Kamal Perera', null, 'kamal@example.com', '0771239999', null, team.projectId,
                    'Matching Budget', null);
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
        }

        System.assertEquals(Label.Partner_Portal_No_Access, refused);
        System.assertEquals(0, [SELECT COUNT() FROM Lead], 'Nothing saved');
    }

    // What the partner is told comes from the channel partner lead rules (LeadLogicController): another CP's customer
    // is created with the notice; the same number in another project is simply a new lead
    @isTest
    static void thePartnerIsToldWhatTheLeadRulesDecided() {
        useSettings();
        Team team = newTeam();
        Lead outsiders = newLead('Outsider Buyer', 'Assigned', team.outsider.Id, team.projectId);
        insert outsiders;
        Project__c another = TestRecordDefaults.project('Another Project', true);
        insert another;

        partnerWebPortalLeadController.CreateLeadResult otherCp;
        partnerWebPortalLeadController.CreateLeadResult otherProject;
        System.runAs(team.partner) {
            otherCp = partnerWebPortalLeadController.createLead('Kamal Perera', null, 'kamal@example.com', outsiders.Phone, null,
                team.projectId, 'Matching Budget', null);
            otherProject = partnerWebPortalLeadController.createLead('Kamal Perera', null, 'kamal2@example.com', outsiders.Phone, null,
                another.Id, 'Matching Budget', null);
        }

        System.assertEquals(LeadLogicController.CP_CREATED_WITH_NOTICE, otherCp.outcome);
        System.assertEquals(Label.CP_Lead_Other_CP_Notice, otherCp.message);
        System.assertNotEquals(null, otherCp.leadId, 'The lead is created');
        System.assertEquals(LeadLogicController.CP_CREATED, otherProject.outcome, 'Phone + Project: another project is not a duplicate');
        System.assertEquals(null, otherProject.message);
    }

    @isTest
    static void offersTheProjectsAndBudgetsOfTheForm() {
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        insert TestRecordDefaults.project('Leads Test Project', true);

        System.assertEquals('Leads Test Project', partnerWebPortalLeadController.getProjectOptions()[0].get('label'));
        System.assert(!partnerWebPortalLeadController.getBudgetOptions().isEmpty());
    }

    @isTest
    static void theChipsAreTheOrgsLeadFiltersInOrder() {
        List<partnerWebPortalLeadController.LeadFilter> chips = partnerWebPortalLeadController.getLeadFilters();

        System.assert(!chips.isEmpty(), 'The Partner Portal Lead Filter records');
        Decimal previous = null;
        Map<String, Partner_Portal_Lead_Filter__mdt> records = Partner_Portal_Lead_Filter__mdt.getAll();
        for (partnerWebPortalLeadController.LeadFilter chip : chips) {
            Decimal order = records.get(chip.key).Order__c;
            System.assert(previous == null || order == null || order >= previous, 'In Order: ' + chip.label);
            previous = order == null ? previous : order;
            System.assertEquals(records.get(chip.key).MasterLabel, chip.label);
        }
    }

    // An executive sees only their own leads, in the projects their channel head gave them, and adds leads only there
    @isTest
    static void anExecutiveSeesAndAddsLeadsOnlyInTheirOwnProjects() {
        useSettings();
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        Project__c given = TestRecordDefaults.project('Given Project', true);
        Project__c other = TestRecordDefaults.project('Other Project', true);
        Project__c closed = TestRecordDefaults.project('Closed Project', false);
        insert new List<Project__c>{ given, other, closed };
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>{ given.Id, closed.Id });
        Id executiveAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :executive.Id].Contact.AccountId;
        Id headAccountId = [SELECT Channel_Head__c FROM Account WHERE Id = :executiveAccountId].Channel_Head__c;
        insert new List<Lead>{
            newLead('Own Given Buyer', 'Assigned', executiveAccountId, given.Id),
            newLead('Own Other Buyer', 'Assigned', executiveAccountId, other.Id),
            newLead('Head Given Buyer', 'Assigned', headAccountId, given.Id)
        };

        Set<String> shown;
        Set<String> byOtherProject;
        List<Map<String, String>> projects;
        String refused;
        Id created;
        System.runAs(executive) {
            shown = namesOf(partnerWebPortalLeadController.getLeads('All', '', 1, 50));
            byOtherProject = namesOf(partnerWebPortalLeadController.getLeads('All', 'Other Project', 1, 50));
            projects = partnerWebPortalLeadController.getProjectOptions();
            try {
                partnerWebPortalLeadController.createLead('Kamal Perera', null, 'kamal@example.com', '0771239998', null, other.Id, 'Matching Budget', null);
            } catch (AuraHandledException e) {
                refused = e.getMessage();
            }
            created = partnerWebPortalLeadController.createLead('Kamal Perera', null, 'kamal@example.com', '0771239997', null, given.Id, 'Matching Budget', null).leadId;
        }

        System.assertEquals(new Set<String>{ 'Own Given Buyer' }, shown, 'Not their lead in another project, nor their channel head\'s');
        System.assertEquals(new Set<String>(), byOtherProject, 'Searching a project they were not given finds nothing');
        System.assertEquals(1, projects.size(), 'Only their active project: ' + projects);
        System.assertEquals('Given Project', projects[0].get('label'));
        System.assertEquals('Please select one of your projects', refused);
        System.assertEquals(executiveAccountId, [SELECT Channel_Partner__c FROM Lead WHERE Id = :created].Channel_Partner__c);
    }
}