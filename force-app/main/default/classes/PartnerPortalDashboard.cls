// The Dashboard of the partner portal. Every figure covers what the logged-in partner may see (PartnerPortalAccess): a
// channel head's own records and their executives', an executive's own records in their projects. The same records
// the Leads, Site Visits and My Team pages show. Partners cannot see their executives' records, so this runs without
// sharing and in system mode, and every query is limited by PartnerPortalAccess.
public without sharing class PartnerPortalDashboard {

    private static final String SETTINGS_RECORD = 'Default';

    // The Partner Portal Setting and the Leads page filters it names; tests set their own
    @TestVisible
    private static Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance(SETTINGS_RECORD);
    @TestVisible
    private static Map<String, Partner_Portal_Lead_Filter__mdt> leadFilters = Partner_Portal_Lead_Filter__mdt.getAll();

    // The logged-in user for the portal's shell: their name, whether they are an executive (no My Team for them), and
    // whether their access has ended, in which case the shell shows only its Access Ended screen (Access Terminated when
    // the partner, or an executive's channel head, was terminated). That stops a partner who got in some other way than
    // the portal's login page, or whose session outlived the access.
    public class PortalUser {
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isExecutive = false;
        @AuraEnabled public Boolean accessEnded = false;
        @AuraEnabled public Boolean terminated = false;
        // For the shell to ask, once Salesforce refuses its requests, what became of this session
        // (partnerPortalLoginController.sessionState); only a partner has one
        @AuraEnabled public String sessionKey;
    }

    @AuraEnabled(cacheable=true)
    public static PortalUser getPortalUser() {
        PortalUser portalUser = new PortalUser();
        portalUser.name = getCurrentUser();
        Account partner = partnerAccount();
        portalUser.accessEnded = partner != null && PartnerTemporaryAccess.isDenied(partner);
        portalUser.terminated = portalUser.accessEnded && PartnerTemporaryAccess.isTerminated(partner);
        portalUser.sessionKey = partner == null ? null : partnerPortalLoginController.sessionKeyOf(UserInfo.getUserId());
        // Only worked out while the access lasts: once it has ended the shell shows no pages to choose from
        portalUser.isExecutive = !portalUser.accessEnded && PartnerPortalAccess.current().isExecutive;
        return portalUser;
    }

    // The logged-in partner's account with what decides whether their access has ended (PartnerTemporaryAccess): the
    // account, or an executive's channel head, is Access Denied or Terminated, or its temporary access ended without its
    // conditions met. Null for a user without a partner account (an internal user previewing the site), who has no
    // partner access to end.
    private static Account partnerAccount() {
        User me = [
            SELECT Contact.AccountId, Contact.Account.Id, Contact.Account.Partner_Type__c, Contact.Account.Temporary_Access_Start_Date__c,
                Contact.Account.Temporary_Access_End_Date__c, Contact.Account.Channel_Head__c, Contact.Account.Channel_Head__r.Id,
                Contact.Account.Channel_Head__r.Partner_Type__c, Contact.Account.Channel_Head__r.Temporary_Access_Start_Date__c,
                Contact.Account.Channel_Head__r.Temporary_Access_End_Date__c
            FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE
        ];
        return me.Contact == null || me.Contact.AccountId == null ? null : me.Contact.Account;
    }

    public class DashboardFigures {
        @AuraEnabled public Integer totalLeads = 0;
        @AuraEnabled public Integer activePipeline = 0;
        @AuraEnabled public Integer siteVisits = 0;
        @AuraEnabled public Integer bookings = 0;
        @AuraEnabled public Integer sales = 0;
        @AuraEnabled public Integer conversionRate = 0;
        @AuraEnabled public Decimal salesRevenue = 0;
        @AuraEnabled public String currencyCode;
    }

    // Not cacheable, so the figures are current each time the Dashboard opens
    @AuraEnabled
    public static DashboardFigures getDashboard() {
        DashboardFigures figures = new DashboardFigures();
        figures.currencyCode = UserInfo.getDefaultCurrency();
        PartnerPortalAccess access = PartnerPortalAccess.current();
        if (access.accountId == null) {
            return figures;
        }

        Map<String, Object> binds = new Map<String, Object>{
            'pipelineStatuses' => valuesOf(filterNamed(setting == null ? null : setting.Pipeline_Lead_Filter__c), 'Lead_Statuses__c'),
            'lostStages' => valuesOf(filterNamed(setting == null ? null : setting.Lost_Lead_Filter__c), 'Opportunity_Stages__c'),
            'bookingStages' => partnerWebPortalMyTeamController.bookingStages()
        };
        String leads = access.leads(binds);
        String opportunities = access.opportunities(binds);

        // Leads the team generated, and the share of them that were converted
        figures.totalLeads = count('Lead', leads, binds);
        Integer converted = count('Lead', leads + ' AND IsConverted = true', binds);
        figures.conversionRate = figures.totalLeads == 0 ? 0
            : (Decimal.valueOf(converted * 100) / figures.totalLeads).setScale(0, System.RoundingMode.HALF_UP).intValue();

        // The Leads page's pipeline filter, plus converted leads whose opportunity is not lost
        figures.activePipeline = count('Lead', leads + ' AND ((IsConverted = false AND Status IN :pipelineStatuses)'
            + ' OR (IsConverted = true AND ConvertedOpportunityId != null AND ConvertedOpportunity.StageName NOT IN :lostStages))', binds);

        // Site visits, not the requests waiting for approval or rejected, nor visits the customer did not come to
        String visits = access.visits(binds);
        List<String> notVisits = notVisitStatuses();
        if (!notVisits.isEmpty()) {
            binds.put('notVisits', notVisits);
            visits += ' AND (Status__c = null OR Status__c NOT IN :notVisits)';
        }
        figures.siteVisits = count('Visit__c', visits, binds);

        // Bookings are past SPA Signing, as on My Team; Sales are all the team's opportunities that are not lost
        figures.bookings = count('Opportunity', opportunities + ' AND StageName IN :bookingStages', binds);
        String sales = opportunities + ' AND StageName NOT IN :lostStages';
        figures.sales = count('Opportunity', sales, binds);
        List<AggregateResult> revenue = (List<AggregateResult>) Database.queryWithBinds(
            'SELECT SUM(Amount) revenue FROM Opportunity WHERE ' + sales, binds, AccessLevel.SYSTEM_MODE);
        Decimal total = revenue.isEmpty() ? null : (Decimal) revenue[0].get('revenue');
        figures.salesRevenue = total == null ? 0 : total;
        return figures;
    }

    @AuraEnabled(cacheable=true)
    public static String getCurrentUser() {
        return [SELECT Name FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE].Name;
    }

    private static Integer count(String objectName, String condition, Map<String, Object> binds) {
        return Database.countQueryWithBinds('SELECT COUNT() FROM ' + objectName + ' WHERE ' + condition, binds, AccessLevel.SYSTEM_MODE);
    }

    // The visit statuses that are not site visits: requests (the Visit Request Status, the Visit Rejected Status) and
    // visits the customer did not come to (the Not Visited Status) of the Partner Portal Setting
    private static List<String> notVisitStatuses() {
        List<String> statuses = new List<String>();
        for (String status : new List<String>{
                setting == null ? null : setting.Visit_Request_Status__c, setting == null ? null : setting.Visit_Rejected_Status__c,
                setting == null ? null : setting.Not_Visited_Status__c }) {
            if (String.isNotBlank(status)) {
                statuses.add(status.trim());
            }
        }
        return statuses;
    }

    private static Partner_Portal_Lead_Filter__mdt filterNamed(String name) {
        return String.isBlank(name) ? null : leadFilters.get(name.trim());
    }

    // The comma-separated values of one of the filter's fields; none without the filter
    private static List<String> valuesOf(Partner_Portal_Lead_Filter__mdt filter, String fieldName) {
        List<String> values = new List<String>();
        String text = filter == null ? null : (String) filter.get(fieldName);
        if (String.isNotBlank(text)) {
            for (String value : text.split(',')) {
                if (String.isNotBlank(value)) {
                    values.add(value.trim());
                }
            }
        }
        return values;
    }
}