@isTest
private class PartnerPortalDashboardTest {

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

    private static Integer leadCount = 0;

    // The org's setting, filters and booking stages as the user defined them
    private static void useSettings() {
        PartnerPortalDashboard.setting = new Partner_Portal_Setting__mdt(Pipeline_Lead_Filter__c = 'Active_Nurturing', Lost_Lead_Filter__c = 'Lost',
            Visit_Request_Status__c = 'Requested', Visit_Rejected_Status__c = 'Rejected', Not_Visited_Status__c = 'Not Visited');
        List<Partner_Portal_Lead_Filter__mdt> filters = (List<Partner_Portal_Lead_Filter__mdt>) JSON.deserialize(JSON.serialize(
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'DeveloperName' => 'Active_Nurturing', 'MasterLabel' => 'Active/Nurturing',
                    'Lead_Statuses__c' => 'New, Assigned, In-Discussion, Contacted, Qualified' },
                new Map<String, Object>{ 'DeveloperName' => 'Lost', 'MasterLabel' => 'Lost', 'Opportunity_Stages__c' => 'Closed Lost, Cancelled' }
            }), List<Partner_Portal_Lead_Filter__mdt>.class);
        PartnerPortalDashboard.leadFilters = new Map<String, Partner_Portal_Lead_Filter__mdt>{ 'Active_Nurturing' => filters[0], 'Lost' => filters[1] };
        partnerWebPortalMyTeamController.setting = new Partner_Portal_Setting__mdt(
            Bookings_After_Stage__c = 'SPA Signing', Stages_Not_Counted_As_Bookings__c = 'Cancelled');
    }

    // The temporary access rules of the shell tests: 1 conversion or 3 completed visits
    private static void useAccessRules() {
        PartnerTemporaryAccess.setting = (Partner_Portal_Setting__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'DeveloperName' => 'Default',
            'Exclusive_Converted_Leads__c' => 1,
            'Exclusive_Site_Visits__c' => 3,
            'Completed_Visit_Status__c' => 'Completed'
        }), Partner_Portal_Setting__mdt.class);
    }

    // Once the account is changed as given, whether the shell tells the partner that their access has ended
    private static Boolean accessEndedFor(User partner, Account change) {
        update change;
        PartnerPortalDashboard.PortalUser portalUser;
        System.runAs(partner) {
            portalUser = PartnerPortalDashboard.getPortalUser();
        }
        return portalUser.accessEnded;
    }

    private static Lead newLead(String name, String status, Id channelPartnerId, Id projectId) {
        leadCount++;
        return new Lead(LastName = name, Company = name + ' Holdings', Status = status, Phone = '07712360' + String.valueOf(leadCount).leftPad(2, '0'),
            LeadSource = 'Channel Partner', Budget_Aligned__c = 'Matching Budget', Project__c = projectId, Channel_Partner__c = channelPartnerId,
            Email = 'dashboard' + leadCount + '@example.com');
    }

    // Converts the lead; its opportunity gets the stage, amount and the lead's Channel Partner
    private static void convert(Lead converted, String stage, Decimal amount) {
        Database.LeadConvert conversion = new Database.LeadConvert();
        conversion.setLeadId(converted.Id);
        conversion.setConvertedStatus([SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1].MasterLabel);
        Database.LeadConvertResult result = Database.convertLead(conversion);
        update new Opportunity(Id = result.getOpportunityId(), StageName = stage, Amount = amount, Channel_Partner__c = converted.Channel_Partner__c);
    }

    @isTest
    static void showsTheFiguresOfThePartnersTeam() {
        useSettings();
        useSharePoint();
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :partner.Id].Contact.AccountId;
        Id channelPartnerType = partnerPortalRegistrationController.partnerRecordTypeId();
        Account executive = new Account(Name = 'Amal Perera', RecordTypeId = channelPartnerType, Channel_Head__c = partnerAccountId);
        Account outsider = new Account(Name = 'Other Partner', RecordTypeId = channelPartnerType);
        insert new List<Account>{ executive, outsider };
        Project__c project = TestRecordDefaults.project('Dashboard Test Project', true);
        insert project;

        Map<String, Lead> leads = new Map<String, Lead>{
            'new' => newLead('New Buyer', 'New', partnerAccountId, project.Id),
            'assigned' => newLead('Assigned Buyer', 'Assigned', partnerAccountId, project.Id),
            'visited' => newLead('Visited Buyer', 'Visited', executive.Id, project.Id),
            'booked' => newLead('Booked Buyer', 'Qualified', executive.Id, project.Id),
            'cancelled' => newLead('Cancelled Buyer', 'Qualified', partnerAccountId, project.Id),
            'proposal' => newLead('Proposal Buyer', 'Qualified', executive.Id, project.Id),
            'outsider' => newLead('Outsider Buyer', 'New', outsider.Id, project.Id)
        };
        insert leads.values();
        convert(leads.get('booked'), 'Tranche Payment', 1000);
        convert(leads.get('cancelled'), 'Cancelled', 700);
        convert(leads.get('proposal'), 'Proposal/Quotation', 300);
        insert new List<Opportunity>{
            new Opportunity(Name = 'Executive Handover', StageName = 'Handover', CloseDate = Date.today(), Amount = 500, Channel_Partner__c = executive.Id),
            new Opportunity(Name = 'Outsider Handover', StageName = 'Handover', CloseDate = Date.today(), Amount = 9999, Channel_Partner__c = outsider.Id)
        };
        insert new List<Visit__c>{
            new Visit__c(Channel_Partner__c = partnerAccountId),
            new Visit__c(Lead__c = leads.get('visited').Id),
            new Visit__c(Channel_Partner__c = outsider.Id),
            // Requests waiting for approval or rejected are not site visits, nor are visits the customer did not come to
            new Visit__c(Channel_Partner__c = partnerAccountId, Status__c = 'Requested'),
            new Visit__c(Channel_Partner__c = partnerAccountId, Status__c = 'Rejected'),
            new Visit__c(Channel_Partner__c = partnerAccountId, Status__c = 'Not Visited')
        };

        PartnerPortalDashboard.DashboardFigures figures;
        Test.startTest();
        System.runAs(partner) {
            figures = PartnerPortalDashboard.getDashboard();
        }
        Test.stopTest();

        System.assertEquals(6, figures.totalLeads, 'The partner\'s and their executive\'s leads, not another team\'s');
        System.assertEquals(4, figures.activePipeline, 'New and Assigned, plus the converted leads whose deal is not cancelled');
        System.assertEquals(2, figures.siteVisits, 'By the visit\'s or its lead\'s Channel Partner');
        System.assertEquals(2, figures.bookings, 'Tranche Payment and Handover are past SPA Signing');
        System.assertEquals(3, figures.sales, 'Every team opportunity that is not cancelled');
        System.assertEquals(50, figures.conversionRate, '3 of the 6 leads were converted');
        System.assertEquals(1800, figures.salesRevenue, 'The amounts of the sales: 1000 + 300 + 500');
        System.assertEquals(UserInfo.getDefaultCurrency(), figures.currencyCode);
    }

    @isTest
    static void aPartnerWithNothingYetSeesZeros() {
        useSettings();
        User partner = PartnerPortalTestUser.create();

        PartnerPortalDashboard.DashboardFigures figures;
        System.runAs(partner) {
            figures = PartnerPortalDashboard.getDashboard();
        }

        System.assertEquals(0, figures.totalLeads);
        System.assertEquals(0, figures.conversionRate, 'No division by zero');
        System.assertEquals(0, figures.salesRevenue);
    }

    @isTest
    static void aUserWithoutAPartnerAccountHasNoFigures() {
        PartnerPortalDashboard.DashboardFigures figures = PartnerPortalDashboard.getDashboard();

        System.assertEquals(0, figures.totalLeads);
        System.assertEquals(0, figures.sales);
        System.assertEquals(UserInfo.getName(), PartnerPortalDashboard.getCurrentUser());
    }

    @isTest
    static void readsTheOrgsSettingAndFilters() {
        // Without overrides the class reads the Default setting and the Leads page filters it names
        System.assertNotEquals(null, PartnerPortalDashboard.setting);
        System.assert(PartnerPortalDashboard.leadFilters.containsKey(PartnerPortalDashboard.setting.Pipeline_Lead_Filter__c),
            'The pipeline filter the setting names exists');
        System.assert(PartnerPortalDashboard.leadFilters.containsKey(PartnerPortalDashboard.setting.Lost_Lead_Filter__c),
            'The lost filter the setting names exists');
    }

    // An executive's figures: only their own records, in the projects their channel head gave them
    @isTest
    static void anExecutiveSeesOnlyTheirOwnFiguresInTheirProjects() {
        useSettings();
        useSharePoint();
        Project__c given = TestRecordDefaults.project('Given Project', true);
        Project__c other = TestRecordDefaults.project('Other Project', true);
        insert new List<Project__c>{ given, other };
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>{ given.Id });
        Id executiveAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :executive.Id].Contact.AccountId;
        Id headAccountId = [SELECT Channel_Head__c FROM Account WHERE Id = :executiveAccountId].Channel_Head__c;
        insert new List<Lead>{
            newLead('Own Given Buyer', 'New', executiveAccountId, given.Id),
            newLead('Own Other Buyer', 'New', executiveAccountId, other.Id),
            newLead('Head Given Buyer', 'New', headAccountId, given.Id)
        };
        insert new List<Opportunity>{
            new Opportunity(Name = 'Own Given', StageName = 'Handover', CloseDate = Date.today(), Amount = 100, Channel_Partner__c = executiveAccountId, Project__c = given.Id),
            new Opportunity(Name = 'Own Other', StageName = 'Handover', CloseDate = Date.today(), Amount = 200, Channel_Partner__c = executiveAccountId, Project__c = other.Id),
            new Opportunity(Name = 'Own No Project', StageName = 'Tranche Payment', CloseDate = Date.today(), Amount = 50, Channel_Partner__c = executiveAccountId),
            new Opportunity(Name = 'Head Given', StageName = 'Handover', CloseDate = Date.today(), Amount = 400, Channel_Partner__c = headAccountId, Project__c = given.Id)
        };
        insert new List<Visit__c>{
            new Visit__c(Channel_Partner__c = executiveAccountId, Project__c = given.Id),
            new Visit__c(Channel_Partner__c = executiveAccountId, Project__c = other.Id),
            new Visit__c(Channel_Partner__c = headAccountId, Project__c = given.Id)
        };

        PartnerPortalDashboard.DashboardFigures figures;
        PartnerPortalDashboard.PortalUser portalUser;
        System.runAs(executive) {
            figures = PartnerPortalDashboard.getDashboard();
            portalUser = PartnerPortalDashboard.getPortalUser();
        }

        System.assertEquals(1, figures.totalLeads, 'Their lead in their project only');
        System.assertEquals(1, figures.activePipeline);
        System.assertEquals(1, figures.siteVisits);
        System.assertEquals(2, figures.bookings, 'Their opportunity in their project, and the one without a project');
        System.assertEquals(2, figures.sales);
        System.assertEquals(150, figures.salesRevenue);
        System.assertEquals(true, portalUser.isExecutive, 'The portal hides My Team for them');
        System.assertEquals(false, portalUser.accessEnded);
    }

    // The shell's Access Ended screen, however the partner logged in: from the day after the end date of a temporary
    // access that ended without its conditions met, and for an Access Denied or Terminated account. The portal is there
    // on the end date itself, for an Exclusive partner, and for a user without a partner account.
    @isTest
    static void tellsTheShellWhenThePartnersAccessHasEnded() {
        useAccessRules();
        useSharePoint();
        User partner = PartnerPortalTestUser.create();
        Id accountId = [SELECT Contact.AccountId FROM User WHERE Id = :partner.Id].Contact.AccountId;
        Date today = PartnerTemporaryAccess.today();

        Map<String, Boolean> ended = new Map<String, Boolean>();
        Test.startTest();
        ended.put('end date', accessEndedFor(partner, new Account(Id = accountId, Partner_Type__c = 'Temporary',
            Temporary_Access_Start_Date__c = today.addDays(-30), Temporary_Access_End_Date__c = today)));
        ended.put('day after', accessEndedFor(partner, new Account(Id = accountId, Temporary_Access_Start_Date__c = today.addDays(-31),
            Temporary_Access_End_Date__c = today.addDays(-1))));
        ended.put('Access Denied', accessEndedFor(partner, new Account(Id = accountId, Partner_Type__c = 'Access Denied')));
        ended.put('Terminated', accessEndedFor(partner, new Account(Id = accountId, Partner_Type__c = 'Terminated')));
        ended.put('Exclusive', accessEndedFor(partner, new Account(Id = accountId, Partner_Type__c = 'Exclusive')));
        Test.stopTest();

        System.assertEquals(false, ended.get('end date'), 'The end date is still part of the access');
        System.assertEquals(true, ended.get('day after'), 'Ended without its conditions met');
        System.assertEquals(true, ended.get('Access Denied'));
        System.assertEquals(true, ended.get('Terminated'));
        System.assertEquals(false, ended.get('Exclusive'));
        System.assertEquals(false, PartnerPortalDashboard.getPortalUser().accessEnded, 'An internal user has no partner access to end');
    }

    private static PartnerPortalDashboard.PortalUser portalUserOf(User partner) {
        PartnerPortalDashboard.PortalUser portalUser;
        System.runAs(partner) {
            portalUser = PartnerPortalDashboard.getPortalUser();
        }
        return portalUser;
    }

    // The shell shows Access Terminated instead of Access Ended when the ended access is a termination: of the partner
    // itself (an executive can be terminated alone) or of an executive's channel head
    @isTest
    static void tellsTheShellWhenThePartnerWasTerminated() {
        useSharePoint();
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>());
        Account own = [SELECT Contact.Account.Id, Contact.Account.Channel_Head__c FROM User WHERE Id = :executive.Id].Contact.Account;

        Test.startTest();
        update new Account(Id = own.Channel_Head__c, Partner_Type__c = 'Exclusive');
        PartnerPortalDashboard.PortalUser withAccess = portalUserOf(executive);
        update new Account(Id = own.Channel_Head__c, Partner_Type__c = 'Access Denied');
        PartnerPortalDashboard.PortalUser headDenied = portalUserOf(executive);
        update new Account(Id = own.Channel_Head__c, Partner_Type__c = 'Terminated');
        PartnerPortalDashboard.PortalUser headTerminated = portalUserOf(executive);
        update new List<Account>{ new Account(Id = own.Channel_Head__c, Partner_Type__c = 'Exclusive'), new Account(Id = own.Id, Partner_Type__c = 'Terminated') };
        PartnerPortalDashboard.PortalUser ownTermination = portalUserOf(executive);
        Test.stopTest();

        System.assertEquals(false, withAccess.accessEnded);
        System.assertEquals(false, withAccess.terminated);
        System.assertEquals(true, headDenied.accessEnded);
        System.assertEquals(false, headDenied.terminated, 'Access Denied is not a termination');
        System.assertEquals(true, headTerminated.accessEnded);
        System.assertEquals(true, headTerminated.terminated);
        System.assertEquals(true, ownTermination.accessEnded);
        System.assertEquals(true, ownTermination.terminated, 'An executive terminated alone');
        System.assertEquals(partnerPortalLoginController.sessionKeyOf(executive.Id), withAccess.sessionKey, 'The shell gets the login\'s session key');
        System.assertEquals(withAccess.sessionKey, ownTermination.sessionKey, 'The key outlives the access');
        System.assertEquals(null, PartnerPortalDashboard.getPortalUser().sessionKey, 'An internal user has no partner session to ask about');
    }

    // An executive goes by their channel head: their portal ends on the same day as the head's
    @isTest
    static void anExecutivesAccessEndsWithTheirChannelHeads() {
        useAccessRules();
        useSharePoint();
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>());
        Id headId = [SELECT Contact.Account.Channel_Head__c FROM User WHERE Id = :executive.Id].Contact.Account.Channel_Head__c;
        Date today = PartnerTemporaryAccess.today();

        Test.startTest();
        Boolean onTheEndDate = accessEndedFor(executive, new Account(Id = headId, Partner_Type__c = 'Temporary',
            Temporary_Access_Start_Date__c = today.addDays(-30), Temporary_Access_End_Date__c = today));
        Boolean dayAfter = accessEndedFor(executive, new Account(Id = headId, Temporary_Access_Start_Date__c = today.addDays(-31),
            Temporary_Access_End_Date__c = today.addDays(-1)));
        Test.stopTest();

        System.assertEquals(false, onTheEndDate);
        System.assertEquals(true, dayAfter, 'Their channel head\'s access ended without its conditions met');
    }
}