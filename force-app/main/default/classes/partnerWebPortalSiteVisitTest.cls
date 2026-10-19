@isTest
private class partnerWebPortalSiteVisitTest {

    // Refuses the folder, so the folder job of the test project ends quietly
    private class SharePointMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(503);
            res.setBody('{"error":{"code":"serviceNotAvailable"}}');
            return res;
        }
    }

    // The refusing mock, with a test token and library (no sign-in, no site lookup)
    private static void useSharePoint() {
        SharePointService.testDriveId = 'test-drive';
        Test.setMock(HttpCalloutMock.class, new SharePointMock());
    }

    // A partner, their executive and another team's partner, with the team's leads and visits
    private class Team {
        User partner;
        Id partnerAccountId;
        Account executive;
        Account outsider;
        Project__c project;
        Map<String, Lead> leads = new Map<String, Lead>();
        Map<String, Visit__c> visits = new Map<String, Visit__c>();
    }

    private static Integer leadCount = 0;

    // The JKP CP Executive (with a manager, the CP Manager) who approves the partners' requests
    private static void useApprovers() {
        Id adminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        User manager = approver(adminProfileId, 'svmgr', null);
        User executive;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert manager;
            executive = approver(adminProfileId, 'svexec', manager.Id);
            insert executive;
        }
        PartnerSiteVisitService.setting = new Partner_Portal_Setting__mdt(Visit_Status__c = 'Upcoming', Visit_Request_Status__c = 'Requested',
            Visit_Rejected_Status__c = 'Rejected', Open_Visit_Statuses__c = 'Upcoming', Completed_Visit_Status__c = 'Completed',
            CP_Executive_Username__c = executive.Username);
    }

    private static User approver(Id profileId, String alias, Id managerId) {
        return new User(ProfileId = profileId, Alias = alias, LastName = 'Approver ' + alias, Email = alias + '@example.com',
            Username = alias + '.' + UserInfo.getOrganizationId() + '@site-visit-test.example.com', EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', TimeZoneSidKey = 'Asia/Colombo', ManagerId = managerId);
    }

    private static String requirementType() {
        return PartnerSiteVisitService.requirementTypes()[0].get('value');
    }

    private static Lead newLead(String name, Id channelPartnerId, Id projectId) {
        return newLead(name, channelPartnerId, projectId, UserInfo.getUserId());
    }

    // A lead of the channel partner, owned by the given user (a partner's own lead is owned by its portal user)
    private static Lead newLead(String name, Id channelPartnerId, Id projectId, Id ownerId) {
        leadCount++;
        return new Lead(LastName = name, Company = name + ' Holdings', Status = 'Assigned', Phone = '07712350' + String.valueOf(leadCount).leftPad(2, '0'),
            LeadSource = 'Channel Partner', Budget_Aligned__c = 'Matching Budget', Project__c = projectId, Channel_Partner__c = channelPartnerId,
            Email = 'visit' + leadCount + '@example.com', OwnerId = ownerId);
    }

    // The visits a team can own: one by its own Channel Partner, one by its lead's, one without a status, an executive's
    // cancelled one, and another team's that never shows
    private static Team newTeam() {
        useSharePoint();
        partnerWebPortalSiteVisit.setting = new Partner_Portal_Setting__mdt(Visit_Status__c = 'Upcoming');
        useApprovers();
        Team team = new Team();
        team.partner = PartnerPortalTestUser.create();
        team.partnerAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :team.partner.Id].Contact.AccountId;
        Id channelPartnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        team.executive = new Account(Name = 'Amal Perera', RecordTypeId = channelPartnerType, Channel_Head__c = team.partnerAccountId);
        team.outsider = new Account(Name = 'Other Partner', RecordTypeId = channelPartnerType);
        insert new List<Account>{ team.executive, team.outsider };
        team.project = TestRecordDefaults.project('Visit Test Project', true);
        insert team.project;

        team.leads.put('partner', newLead('Partner Buyer', team.partnerAccountId, team.project.Id, team.partner.Id));
        team.leads.put('executive', newLead('Executive Buyer', team.executive.Id, team.project.Id));
        team.leads.put('unvisited', newLead('Unvisited Buyer', team.partnerAccountId, team.project.Id, team.partner.Id));
        team.leads.put('executiveOpen', newLead('Executive Open Buyer', team.executive.Id, team.project.Id));
        team.leads.put('outsider', newLead('Outsider Buyer', team.outsider.Id, team.project.Id));
        insert team.leads.values();

        team.visits.put('own', new Visit__c(Channel_Partner__c = team.partnerAccountId, Status__c = 'Completed'));
        team.visits.put('lead', new Visit__c(Lead__c = team.leads.get('executive').Id, Status__c = 'Upcoming'));
        team.visits.put('blank', new Visit__c(Lead__c = team.leads.get('partner').Id));
        team.visits.put('cancelled', new Visit__c(Channel_Partner__c = team.executive.Id, Status__c = 'Cancelled', Project__c = team.project.Id));
        team.visits.put('outsider', new Visit__c(Lead__c = team.leads.get('outsider').Id, Status__c = 'Completed'));
        insert team.visits.values();
        return team;
    }

    private static Set<String> namesOf(partnerWebPortalSiteVisit.SiteVisitsResponse response) {
        Set<String> names = new Set<String>();
        for (partnerWebPortalSiteVisit.VisitRow row : response.visits) {
            names.add(row.visitName);
        }
        return names;
    }

    private static Map<Id, String> visitNames(Team team) {
        Map<Id, String> names = new Map<Id, String>();
        for (Visit__c visit : [SELECT Name FROM Visit__c WHERE Id IN :team.visits.values()]) {
            names.put(visit.Id, visit.Name);
        }
        return names;
    }

    @isTest
    static void eachStatusShowsTheTeamsVisits() {
        Team team = newTeam();
        Map<Id, String> names = visitNames(team);

        Map<String, Set<String>> shown = new Map<String, Set<String>>();
        List<String> chips;
        System.runAs(team.partner) {
            chips = partnerWebPortalSiteVisit.getStageOptions();
            for (String chip : chips) {
                shown.put(chip, namesOf(partnerWebPortalSiteVisit.getSiteVisit(chip, '', 1, 50)));
            }
        }

        System.assertEquals('All', chips[0]);
        System.assertEquals(new Set<String>{ names.get(team.visits.get('own').Id), names.get(team.visits.get('lead').Id),
            names.get(team.visits.get('blank').Id), names.get(team.visits.get('cancelled').Id) }, shown.get('All'),
            'Visits of the partner and their executive, by the visit\'s or the lead\'s Channel Partner, not another team\'s');
        System.assertEquals(new Set<String>{ names.get(team.visits.get('own').Id) }, shown.get('Completed'));
        System.assertEquals(new Set<String>{ names.get(team.visits.get('lead').Id), names.get(team.visits.get('blank').Id) }, shown.get('Upcoming'),
            'A visit without a status is Upcoming');
        System.assertEquals(new Set<String>{ names.get(team.visits.get('cancelled').Id) }, shown.get('Cancelled'));
    }

    @isTest
    static void rowsShowTheCustomerProjectAndStatus() {
        Team team = newTeam();
        Map<Id, String> names = visitNames(team);

        partnerWebPortalSiteVisit.SiteVisitsResponse firstPage;
        partnerWebPortalSiteVisit.SiteVisitsResponse secondPage;
        System.runAs(team.partner) {
            firstPage = partnerWebPortalSiteVisit.getSiteVisit('All', null, 1, 3);
            secondPage = partnerWebPortalSiteVisit.getSiteVisit(null, null, 2, 3);
        }

        System.assertEquals(4, firstPage.totalRecords);
        System.assertEquals(2, firstPage.totalPages);
        System.assertEquals(1, secondPage.visits.size());
        System.assertEquals(4, secondPage.visits[0].rowNo);
        List<partnerWebPortalSiteVisit.VisitRow> rows = new List<partnerWebPortalSiteVisit.VisitRow>(firstPage.visits);
        rows.addAll(secondPage.visits);
        for (partnerWebPortalSiteVisit.VisitRow row : rows) {
            Id visitId = null;
            for (String key : team.visits.keySet()) {
                if (names.get(team.visits.get(key).Id) == row.visitName) {
                    visitId = team.visits.get(key).Id;
                }
            }
            // Whose visit it is: the visit's own Channel Partner, else its lead's
            String expectedPartner = visitId == team.visits.get('lead').Id || visitId == team.visits.get('cancelled').Id
                ? 'Amal Perera' : 'Portal Test Partner';
            System.assertEquals(expectedPartner, row.channelPartner, row.visitName);
            if (row.visitName == names.get(team.visits.get('blank').Id)) {
                System.assertEquals('Partner Buyer', row.leadName);
                System.assertEquals('Visit Test Project', row.projectName, 'The lead\'s project when the visit has none');
                System.assertEquals('Upcoming', row.status);
            } else if (row.visitName == names.get(team.visits.get('own').Id)) {
                System.assertEquals('-', row.leadName);
                System.assertEquals('-', row.projectName);
                System.assertEquals('Completed', row.status);
            }
        }
    }

    @isTest
    static void searchFindsVisitsByWhatTheTableShows() {
        Team team = newTeam();
        Map<Id, String> names = visitNames(team);
        String cancelledName = names.get(team.visits.get('cancelled').Id);

        Map<String, Set<String>> found = new Map<String, Set<String>>();
        System.runAs(team.partner) {
            for (String term : new List<String>{ cancelledName, 'executive buyer', 'Visit Test', 'amal', 'Outsider', '%' }) {
                found.put(term, namesOf(partnerWebPortalSiteVisit.getSiteVisit('All', term, 1, 50)));
            }
        }

        System.assertEquals(new Set<String>{ cancelledName }, found.get(cancelledName), 'By visit name');
        System.assertEquals(new Set<String>{ names.get(team.visits.get('lead').Id) }, found.get('executive buyer'), 'By customer, in any capitals');
        System.assertEquals(3, found.get('Visit Test').size(), 'By project, the visit\'s or its lead\'s');
        System.assertEquals(new Set<String>{ names.get(team.visits.get('lead').Id), cancelledName }, found.get('amal'),
            'By the executive whose visit or lead it is');
        System.assertEquals(new Set<String>(), found.get('Outsider'), 'Never another team\'s visits');
        System.assertEquals(new Set<String>(), found.get('%'), '% is searched for, not a wildcard');
    }

    @isTest
    static void exportsTheChosenStatusForExcel() {
        Team team = newTeam();

        String all;
        String cancelled;
        System.runAs(team.partner) {
            all = partnerWebPortalSiteVisit.exportCSV('All', '');
            cancelled = partnerWebPortalSiteVisit.exportCSV('Cancelled', '');
        }

        List<String> lines = all.split('\r\n');
        System.assertEquals('"Sr.","Visit Created Date","Visit Name","Customer (Lead)","Channel Partner","Project","Visit Date","Visit Status"', lines[0]);
        System.assertEquals(5, lines.size(), all);
        System.assertEquals(2, cancelled.split('\r\n').size(), cancelled);
        System.assert(cancelled.contains('"Amal Perera","Visit Test Project","-","Cancelled"'), cancelled);
        System.assert(!all.contains('Outsider Buyer'));
    }

    // The form sends a request for one of the partner's own leads, for the lead's project (the form shows it read-only;
    // another project is refused); it waits for the JKP CP Executive's approval, and the lead is not offered again while
    // it does
    @isTest
    static void requestsAVisitForThePartnersOwnLead() {
        Team team = newTeam();
        Lead customer = team.leads.get('unvisited');
        // Another active project than the lead's
        Project__c other = TestRecordDefaults.project('Second Project', true);
        insert other;

        List<Map<String, String>> customers;
        List<Map<String, String>> customersAfter;
        List<Map<String, String>> types;
        String otherProject;
        Id visitId;
        System.runAs(team.partner) {
            customers = partnerWebPortalSiteVisit.getCustomerOptions();
            types = partnerWebPortalSiteVisit.getRequirementTypeOptions();
            otherProject = errorOf(customer.Id, other.Id, requirementType(), Date.today().addDays(3), '02:30 PM', 'Family of 4');
            visitId = partnerWebPortalSiteVisit.createSiteVisit(customer.Id, String.valueOf(team.project.Id), requirementType(),
                Date.today().addDays(3), '02:30 PM', ' Family of 4 ');
            customersAfter = partnerWebPortalSiteVisit.getCustomerOptions();
        }

        System.assertEquals(1, customers.size(), 'The partner\'s own open leads without a visit scheduled, not their executive\'s: ' + customers);
        System.assertEquals('Unvisited Buyer', customers[0].get('label'));
        System.assertEquals(String.valueOf(team.project.Id), customers[0].get('projectId'));
        System.assertEquals('Visit Test Project', customers[0].get('projectName'), 'The project the form shows read-only');
        System.assertEquals('', customers[0].get('projectUnavailableReason'), 'Its project is open for site visits');
        System.assertEquals(PartnerSiteVisitService.requirementTypes(), types);
        System.assertEquals(String.format(PartnerSiteVisitService.PARTNER_VISIT_PROJECT_NOT_LEAD, new List<Object>{ 'Visit Test Project' }), otherProject);
        System.assertEquals(0, customersAfter.size(), 'Not while its request waits: ' + customersAfter);

        Visit__c visit = [SELECT Lead__c, Channel_Partner__c, Project__c, Requirement_Type__c, Visit_Date__c, Visit_Time__c, Visit_Description__c,
            Status__c, Approval_Status__c, OwnerId FROM Visit__c WHERE Id = :visitId];
        System.assertEquals(customer.Id, visit.Lead__c);
        System.assertEquals(team.partnerAccountId, visit.Channel_Partner__c, 'The partner whose lead it is');
        System.assertEquals(team.project.Id, visit.Project__c, 'The lead\'s project');
        System.assertEquals(requirementType(), visit.Requirement_Type__c);
        System.assertEquals(Date.today().addDays(3), visit.Visit_Date__c);
        System.assertEquals(Time.newInstance(14, 30, 0, 0), visit.Visit_Time__c);
        System.assertEquals('Family of 4', visit.Visit_Description__c);
        System.assertEquals('Requested', visit.Status__c, 'A request until it is approved');
        System.assertEquals(PartnerSiteVisitService.PENDING_EXECUTIVE, visit.Approval_Status__c);
        System.assertEquals(team.partner.Id, visit.OwnerId);
        System.assertEquals(1, [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :visitId AND Status = 'Pending'], 'Sent for approval');
    }

    // A lead whose project is no longer active is not open for site visits: the form shows why (with the lead), and a
    // request is refused with that reason
    @isTest
    static void aLeadWhoseProjectIsNotOpenGetsNoVisit() {
        Team team = newTeam();
        update new Project__c(Id = team.project.Id, Active__c = false);

        List<Map<String, String>> customers;
        String refusal;
        System.runAs(team.partner) {
            customers = partnerWebPortalSiteVisit.getCustomerOptions();
            refusal = errorOf(team.leads.get('unvisited').Id, team.project.Id, requirementType(), Date.today().addDays(1), '10:00 AM',
                'Family of 4');
        }

        String notOpen = String.format(PartnerSiteVisitService.PARTNER_VISIT_PROJECT_NOT_OPEN, new List<Object>{ 'Visit Test Project' });
        System.assertEquals(1, customers.size(), String.valueOf(customers));
        System.assertEquals('Visit Test Project', customers[0].get('projectName'));
        System.assertEquals(notOpen, customers[0].get('projectUnavailableReason'));
        System.assertEquals(notOpen, refusal);
        System.assertEquals(5, [SELECT COUNT() FROM Visit__c], 'Nothing new is saved');
    }

    // A lead an internal user owns (JKP took it) is not offered on the Site Visits page
    @isTest
    static void aLeadAnInternalUserOwnsIsNotOffered() {
        Team team = newTeam();
        update new Lead(Id = team.leads.get('unvisited').Id, OwnerId = UserInfo.getUserId());

        List<Map<String, String>> customers;
        System.runAs(team.partner) {
            customers = partnerWebPortalSiteVisit.getCustomerOptions();
        }

        System.assertEquals(0, customers.size(), String.valueOf(customers));
    }

    // A lead JKP took over is not offered, and cannot get a visit
    @isTest
    static void aLeadJkpTookOverGetsNoVisit() {
        Team team = newTeam();
        Lead customer = team.leads.get('unvisited');
        update new Lead(Id = customer.Id, OwnerId = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Re_Marketing_Queue'].Id);

        List<Map<String, String>> customers;
        String refusal;
        System.runAs(team.partner) {
            customers = partnerWebPortalSiteVisit.getCustomerOptions();
            refusal = errorOf(customer.Id, team.project.Id, requirementType(), Date.today(), '10:00 AM', 'Family of 4');
        }

        System.assertEquals(0, customers.size(), String.valueOf(customers));
        System.assertEquals(partnerWebPortalSiteVisit.PARTNER_VISIT_LEAD_NOT_OPEN, refusal);
    }

    // Every field is required: customer, project, requirement type, date (today or later), time and description
    @isTest
    static void refusesVisitsThatBreakTheRules() {
        Team team = newTeam();
        String customer = team.leads.get('unvisited').Id;
        String project = team.project.Id;
        Date day = Date.today().addDays(1);

        Map<String, String> errors = new Map<String, String>();
        String type = requirementType();
        System.runAs(team.partner) {
            errors.put('no customer', errorOf('', project, type, day, '10:00 AM', 'Family of 4'));
            errors.put('other team', errorOf(team.leads.get('outsider').Id, project, type, day, '10:00 AM', 'Family of 4'));
            errors.put('executive', errorOf(team.leads.get('executiveOpen').Id, project, type, day, '10:00 AM', 'Family of 4'));
            errors.put('not an id', errorOf('not-an-id', project, type, day, '10:00 AM', 'Family of 4'));
            errors.put('no project', errorOf(customer, '', type, day, '10:00 AM', 'Family of 4'));
            errors.put('project not an id', errorOf(customer, 'not-an-id', type, day, '10:00 AM', 'Family of 4'));
            errors.put('lead as project', errorOf(customer, customer, type, day, '10:00 AM', 'Family of 4'));
            errors.put('project as customer', errorOf(project, project, type, day, '10:00 AM', 'Family of 4'));
            errors.put('no type', errorOf(customer, project, ' ', day, '10:00 AM', 'Family of 4'));
            errors.put('unknown type', errorOf(customer, project, 'Castle', day, '10:00 AM', 'Family of 4'));
            errors.put('no date', errorOf(customer, project, type, null, '10:00 AM', 'Family of 4'));
            errors.put('past date', errorOf(customer, project, type, Date.today().addDays(-1), '10:00 AM', 'Family of 4'));
            errors.put('no time', errorOf(customer, project, type, day, ' ', 'Family of 4'));
            errors.put('bad hour', errorOf(customer, project, type, day, '13:00 PM', 'Family of 4'));
            errors.put('not a time', errorOf(customer, project, type, day, 'soon', 'Family of 4'));
            errors.put('no description', errorOf(customer, project, type, day, '10:00 AM', '  '));
        }

        System.assertEquals('Choose the customer.', errors.get('no customer'));
        System.assertEquals('Choose the customer from your own leads.', errors.get('other team'), 'Another team\'s lead');
        System.assertEquals('Choose the customer from your own leads.', errors.get('executive'), 'An executive works their own leads');
        System.assertEquals('Choose the customer from your own leads.', errors.get('not an id'));
        System.assertEquals('Choose the project.', errors.get('no project'));
        System.assertEquals('Choose the project.', errors.get('project not an id'));
        System.assertEquals('Choose the project.', errors.get('lead as project'), 'Another object\'s Id is not a project');
        System.assertEquals('Choose the customer from your own leads.', errors.get('project as customer'), 'A project Id is not a lead');
        System.assertEquals('Choose the requirement type.', errors.get('no type'));
        System.assertEquals(String.format(PartnerSiteVisitService.PARTNER_LEAD_EDIT_FIELD_REQUIRED, new List<Object>{
            Visit__c.Requirement_Type__c.getDescribe().getLabel() }), errors.get('unknown type'));
        System.assertEquals('Choose the visit date.', errors.get('no date'));
        System.assertEquals(PartnerSiteVisitService.PARTNER_VISIT_DATE_PAST, errors.get('past date'));
        System.assertEquals('Enter the visit time.', errors.get('no time'));
        System.assertEquals('Enter a valid visit time, for example 10:30 AM.', errors.get('bad hour'));
        System.assertEquals('Enter a valid visit time, for example 10:30 AM.', errors.get('not a time'));
        System.assertEquals('Enter a description.', errors.get('no description'));
        System.assertEquals(5, [SELECT COUNT() FROM Visit__c], 'Nothing new is saved');
    }

    // The form's "hh:mm AM/PM" as a time of day, including the hours where 12-hour clocks are easy to get wrong (a 24-hour
    // time is read too)
    @isTest
    static void readsTheFormsTimeOfDay() {
        System.assertEquals(Time.newInstance(0, 0, 0, 0), partnerWebPortalSiteVisit.timeOf('12:00 AM'), 'Midnight');
        System.assertEquals(Time.newInstance(12, 30, 0, 0), partnerWebPortalSiteVisit.timeOf('12:30 PM'), 'Noon');
        System.assertEquals(Time.newInstance(13, 5, 0, 0), partnerWebPortalSiteVisit.timeOf('01:05 PM'));
        System.assertEquals(Time.newInstance(13, 5, 0, 0), partnerWebPortalSiteVisit.timeOf(' 1:05 pm '), 'Spaces and capitals do not matter');
        System.assertEquals(Time.newInstance(9, 45, 0, 0), partnerWebPortalSiteVisit.timeOf('09:45 AM'));
        System.assertEquals(Time.newInstance(14, 30, 0, 0), partnerWebPortalSiteVisit.timeOf('14:30'));
        for (String notATime : new List<String>{ '00:30 AM', '10:60 AM', '1:5 PM', '13:00 PM', 'soon' }) {
            System.assertEquals(null, partnerWebPortalSiteVisit.timeOf(notATime), notATime);
        }
    }

    // The message a partner sees for these details, or null when the request is saved
    private static String errorOf(String leadId, String projectId, String requirementType, Date visitDate, String visitTime, String description) {
        try {
            partnerWebPortalSiteVisit.createSiteVisit(leadId, projectId, requirementType, visitDate, visitTime, description);
            return null;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    @isTest
    static void aUserWithoutAPartnerAccountHasNoVisits() {
        Team team = newTeam();

        System.assertEquals(0, partnerWebPortalSiteVisit.getSiteVisit('All', '', 1, 10).totalRecords);
        System.assertEquals(0, partnerWebPortalSiteVisit.getCustomerOptions().size());
        System.assertEquals(1, partnerWebPortalSiteVisit.exportCSV('All', '').split('\r\n').size(), 'Only the header');
        System.assertEquals('Visit Test Project', partnerWebPortalSiteVisit.getProjectOptions()[0].get('label'));
    }

    // An executive sees and schedules only their own visits, in the projects their channel head gave them, each for the
    // project of its lead
    @isTest
    static void anExecutiveSeesAndSchedulesVisitsOnlyInTheirOwnProjects() {
        useSharePoint();
        partnerWebPortalSiteVisit.setting = new Partner_Portal_Setting__mdt(Visit_Status__c = 'Upcoming');
        useApprovers();
        Project__c given = TestRecordDefaults.project('Given Project', true);
        Project__c other = TestRecordDefaults.project('Other Project', true);
        insert new List<Project__c>{ given, other };
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>{ given.Id });
        Id executiveAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :executive.Id].Contact.AccountId;
        Id headAccountId = [SELECT Channel_Head__c FROM Account WHERE Id = :executiveAccountId].Channel_Head__c;
        Lead visited = newLead('Own Visited Buyer', executiveAccountId, given.Id, executive.Id);
        Lead fresh = newLead('Own Fresh Buyer', executiveAccountId, given.Id, executive.Id);
        Lead elsewhere = newLead('Own Elsewhere Buyer', executiveAccountId, other.Id, executive.Id);
        insert new List<Lead>{ visited, fresh, elsewhere };
        Visit__c ownVisit = new Visit__c(Lead__c = visited.Id, Status__c = 'Upcoming');
        insert new List<Visit__c>{
            ownVisit,
            new Visit__c(Channel_Partner__c = executiveAccountId, Project__c = other.Id, Status__c = 'Upcoming'),
            new Visit__c(Channel_Partner__c = headAccountId, Project__c = given.Id, Status__c = 'Upcoming')
        };

        partnerWebPortalSiteVisit.SiteVisitsResponse visits;
        List<Map<String, String>> projects;
        List<Map<String, String>> customers;
        Set<String> offered;
        String otherProject;
        String otherLead;
        Id scheduled;
        System.runAs(executive) {
            visits = partnerWebPortalSiteVisit.getSiteVisit('All', '', 1, 50);
            projects = partnerWebPortalSiteVisit.getProjectOptions();
            customers = partnerWebPortalSiteVisit.getCustomerOptions();
            offered = partnerWebPortalSiteVisit.offeredProjectIds();
            otherProject = errorOf(fresh.Id, other.Id, requirementType(), Date.today(), '10:00 AM', 'Family of 4');
            otherLead = errorOf(elsewhere.Id, given.Id, requirementType(), Date.today(), '10:00 AM', 'Family of 4');
            scheduled = partnerWebPortalSiteVisit.createSiteVisit(fresh.Id, given.Id, requirementType(), Date.today().addDays(1), '10:00 AM',
                'Family of 4');
        }

        System.assertEquals(1, visits.totalRecords, 'Only their own visit in their project');
        System.assertEquals([SELECT Name FROM Visit__c WHERE Id = :ownVisit.Id].Name, visits.visits[0].visitName);
        System.assertEquals(1, projects.size());
        System.assertEquals('Given Project', projects[0].get('label'));
        System.assertEquals(1, customers.size(), 'Their own open lead in their project without a visit scheduled: ' + customers);
        System.assertEquals('Own Fresh Buyer', customers[0].get('label'));
        System.assertEquals('Given Project', customers[0].get('projectName'));
        System.assertEquals(new Set<String>{ String.valueOf(given.Id) }, offered, 'What an old lead without a project could choose from');
        System.assertEquals(String.format(PartnerSiteVisitService.PARTNER_VISIT_PROJECT_NOT_LEAD, new List<Object>{ 'Given Project' }), otherProject,
            'Not another project than the lead\'s');
        System.assertEquals('Choose the customer from your own leads.', otherLead, 'Their lead in a project they were not given');
        System.assertEquals(executiveAccountId, [SELECT Channel_Partner__c FROM Visit__c WHERE Id = :scheduled].Channel_Partner__c);
    }
}