public without sharing class CustomerPortalController {

    public class MenuItem {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String icon;
        @AuraEnabled public Integer displayOrder;
        @AuraEnabled public Boolean active;
    }

    public class HeaderData {
        @AuraEnabled public String userName;
        @AuraEnabled public String userRole;
        @AuraEnabled public String avatarUrl;
        @AuraEnabled public Integer notificationCount;
    }

    public class PortalData {
        @AuraEnabled public List<MenuItem> menuItems;
        @AuraEnabled public HeaderData headerData;
    }


    public class ProjectImage {
        @AuraEnabled public String url;
        @AuraEnabled public Integer displayOrder;
    }

    public class Amenity {
        @AuraEnabled public String name;
        @AuraEnabled public String icon;
    }

    public class SpecItem {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class Project {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String location;
        @AuraEnabled public String bhk;
        @AuraEnabled public String typeLabel;
        @AuraEnabled public String status; 
        @AuraEnabled public List<ProjectImage> images;

        @AuraEnabled public String priceCurrency;
        @AuraEnabled public String priceValue;
        @AuraEnabled public String possessionDate;
        @AuraEnabled public String homesLeft;

        @AuraEnabled public List<SpecItem> specs;

        @AuraEnabled public List<Amenity> amenities;

        @AuraEnabled public String brochureUrl;
    }


    // Not cacheable: the header shows the customer's current name and picture on every page load (a cached answer could
    // show the old picture after a reload). The profile page also updates the header at once (event 'profileupdated').
    @AuraEnabled
    public static PortalData getPortalData() {
        PortalData result = new PortalData();
        result.menuItems = getSidebarMenu();
        result.headerData = getHeaderData();
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<MenuItem> getSidebarMenu() {
        List<MenuItem> items = new List<MenuItem>();

        items.add(buildMenuItem('Dashboard', 'dashboard', 'utility:apps', 1, true));
        items.add(buildMenuItem('My Properties', 'myProperties', 'utility:home', 2, false));
        items.add(buildMenuItem('Construction status', 'constructionStatus', 'utility:metrics', 3, false));
        items.add(buildMenuItem('My Documents', 'myDocuments', 'utility:file', 4, false));
        items.add(buildMenuItem('My Accounts', 'myAccounts', 'utility:contact', 5, false));
        items.add(buildMenuItem('Projects', 'projects', 'utility:layers', 6, false));
        items.add(buildMenuItem('My Visits', 'myVisits', 'utility:location', 7, false));
        items.add(buildMenuItem('Support', 'support', 'utility:priority', 8, false));
        items.add(buildMenuItem('Referrals', 'referrals', 'utility:people', 9, false));
        items.add(buildMenuItem('Events', 'events', 'utility:favorite', 10, false));
        items.add(buildMenuItem('FAQ\'s', 'faqs', 'utility:help', 11, false));
        items.add(buildMenuItem('Who We Are', 'aboutUs', 'utility:info', 12, false));
        items.add(buildMenuItem('Lets Talk', 'letsTalk', 'utility:chat', 13, false));
        items.add(buildMenuItem('Terms & Conditions', 'termsConditions', 'utility:contract', 14, false));
        items.add(buildMenuItem('Logout', 'logout', 'utility:logout', 15, false));
        return items;
    }

    // The signed-in user's name and the profile picture of their customer account (a data: URL, or null for the default
    // avatar); not cacheable, like getPortalData
    @AuraEnabled
    public static HeaderData getHeaderData() {
        User me = [SELECT Name, Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        HeaderData data = new HeaderData();
        data.userName = me.Name;
        data.userRole = 'Customer';
        data.avatarUrl = me.Contact == null ? null : photoUrlFor(me.Contact.AccountId);
        data.notificationCount = 3;
        return data;
    }

    private static List<Project> buildProjects() {
        List<Project> projects = new List<Project>();

        projects.add(buildProject(
            'PRJ-001',
            'JK Kingsland',
            'A premier residential development offering modern living spaces with world-class amenities.',
            'Plot No-15, VIP Colony, Nayapally, Bhubaneswar',
            '1 BHK',
            'current',
            new List<String>{
                'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800',
                'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=800',
                'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=800'
            },
            'LKR', '1.20 Cr. Onwards', 'May 2025', '12',
            'Residential', '1 BHK', 'All', 'Under Construction', '650 sq ft.', 'Ground Floor',
            'https://example.com/brochures/jk-kingsland.pdf'
        ));

        projects.add(buildProject(
            'PRJ-002',
            'JK Pallaciya',
            'Contemporary apartments designed for comfort and connectivity in the heart of the city.',
            'Plot No-15, VIP Colony, Nayapally, Bhubaneswar',
            '2 BHK',
            'current',
            new List<String>{
                'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=800',
                'https://images.unsplash.com/photo-1571055107559-3e67626fa8be?w=800',
                'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00?w=800'
            },
            'LKR', '1.65 Cr. Onwards', 'August 2025', '09',
            'Residential', '2 BHK', 'Family', 'Under Construction', '820 sq ft.', '3rd Floor',
            'https://example.com/brochures/jk-pallaciya.pdf'
        ));

        projects.add(buildProject(
            'PRJ-003',
            'Vipul Gardens',
            'Spacious 3 & 4 BHK residences surrounded by landscaped gardens and premium facilities.',
            'Plot No-15, VIP Colony, Nayapally, Bhubaneswar',
            '3 & 4 BHK',
            'current',
            new List<String>{
                'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=800',
                'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=800'
            },
            'LKR', '2.45 Cr. Onwards', 'December 2025', '05',
            'Residential', '3 & 4 BHK', 'Family', 'Ready to Move', '1450 sq ft.', 'Multiple',
            'https://example.com/brochures/vipul-gardens.pdf'
        ));

        projects.add(buildProject(
            'PRJ-004',
            'Sunrise Ridge Villas',
            'Exclusive villa community offering privacy, greenery and resort-style amenities.',
            'Plot No-15, VIP Colony, Nayapally',
            '2 BHK',
            'current',
            new List<String>{
                'https://images.unsplash.com/photo-1449844908441-8829872d2607?w=800',
                'https://images.unsplash.com/photo-1600047509807-ba8f99d2cdde?w=800',
                'https://images.unsplash.com/photo-1502005229762-cf1b2da7c5d6?w=800',
                'https://images.unsplash.com/photo-1523217582562-09d0def993a6?w=800'
            },
            'LKR', '1.43 Cr. Onwards', 'June 2021', '07',
            'Residential', '2 BHK', 'All', 'Under Construction', '900 sq ft.', 'Ground Floor',
            'https://example.com/brochures/sunrise-ridge-villas.pdf'
        ));

        projects.add(buildProject(
            'PRJ-005',
            'Harbourview Residency',
            'Waterfront apartments with panoramic harbour views and premium indoor amenities.',
            'Marine Drive, Colombo',
            '1 & 2 BHK',
            'upcoming',
            new List<String>{
                'https://images.unsplash.com/photo-1494526585095-c41746248156?w=800',
                'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=800'
            },
            'LKR', '1.85 Cr. Onwards', 'March 2026', '20',
            'Residential', '1 & 2 BHK', 'All', 'Pre-Launch', '780 sq ft.', 'Multiple',
            'https://example.com/brochures/harbourview-residency.pdf'
        ));

        projects.add(buildProject(
            'PRJ-006',
            'Greenfield Enclave',
            'A sustainable community development with solar-powered common areas and rainwater harvesting.',
            'Kandy Road, Kadawatha',
            '3 BHK',
            'upcoming',
            new List<String>{
                'https://images.unsplash.com/photo-1580587771525-78b9dba3b914?w=800',
                'https://images.unsplash.com/photo-1580216643062-cf460548a66a?w=800',
                'https://images.unsplash.com/photo-1570129477492-45c003edd2be?w=800'
            },
            'LKR', '2.10 Cr. Onwards', 'January 2027', '15',
            'Residential', '3 BHK', 'Family', 'Pre-Launch', '1100 sq ft.', 'Multiple',
            'https://example.com/brochures/greenfield-enclave.pdf'
        ));

        return projects;
    }

    private static Project buildProject(String id,String name,String description,String location,String bhk,String status,List<String> imageUrls,String priceCurrency,String priceValue,String possessionDate,String homesLeft,String specType,String specBhk,String specTenants,String specAvailability,String specArea,String specSlab,String brochureUrl) {    Project p = new Project();
        p.id = id;
        p.name = name;
        p.description = description;
        p.location = location;
        p.bhk = bhk;
        p.typeLabel = 'Type';
        p.status = status;

        p.images = new List<ProjectImage>();
        Integer order = 1;
        for (String url : imageUrls) {
            ProjectImage img = new ProjectImage();
            img.url = url;
            img.displayOrder = order;
            p.images.add(img);
            order++;
        }

        p.priceCurrency = priceCurrency;
        p.priceValue = priceValue;
        p.possessionDate = possessionDate;
        p.homesLeft = homesLeft;

        p.specs = new List<SpecItem>{
            buildSpecItem(specType, 'Type'),
            buildSpecItem(specBhk, 'Type'),
            buildSpecItem(specTenants, 'Tenants'),
            buildSpecItem(specAvailability, 'Availability'),
            buildSpecItem(specArea, 'Area'),
            buildSpecItem(specSlab, 'Slab')
        };

        // p.amenities = new List<Amenity>{
        //     buildAmenity('Water for 24 Hrs', 'utility:water_drop'),
        //     buildAmenity('Garbage Collection', 'utility:delete'),
        //     buildAmenity('Park for Children', 'utility:groups'),
        //     buildAmenity('Swimming Pool', 'utility:water_body')
        // };
        //  p.amenities = new List<Amenity>{
        //     buildAmenity('Water for 24 Hrs', '🚰'),
        //     buildAmenity('Garbage Collection', '🗑️'),
        //     buildAmenity('Park for Children', '🌳'),
        //     buildAmenity('Swimming Pool', '🏊')
        // };

         p.amenities = new List<Amenity>{
            buildAmenity('Water for 24 Hrs', 'water'),
            buildAmenity('Garbage Collection', 'garbage'),
            buildAmenity('Park for Children', 'park'),
            buildAmenity('Swimming Pool', 'pool')
        };

        p.brochureUrl = brochureUrl;

        return p;
    }

    private static SpecItem buildSpecItem(String value, String label) {
        SpecItem item = new SpecItem();
        item.value = value;
        item.label = label;
        return item;
    }

    private static Amenity buildAmenity(String name, String icon) {
        Amenity amenity = new Amenity();
        amenity.name = name;
        amenity.icon = icon;
        return amenity;
    }

    private static MenuItem buildMenuItem(String label, String value, String icon, Integer displayOrder, Boolean active) {
        MenuItem item = new MenuItem();
        item.label = label;
        item.value = value;
        item.icon = icon;
        item.displayOrder = displayOrder;
        item.active = active;
        return item;
    }


      public class ReferralStep {
        @AuraEnabled public Integer stepNumber;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String imageUrl;  
        @AuraEnabled public String iconName;   
    }

    // Refer Now
    private static final String LEAD_QUEUE = 'Lead_Assignment_Queue';
    private static final String REFERRAL_LEAD_SOURCE = 'Referral';
    private static final String REFERRAL_LEAD_STATUS = 'New';
    // A customer's referral counts as a hot lead
    private static final String REFERRAL_CLASSIFICATION = 'Hot';
    @TestVisible private static final String REFERRAL_FIELDS_REQUIRED = 'Choose a property and enter your friend\u2019s name and mobile number.';
    @TestVisible private static final String REFERRAL_NAME_TOO_LONG = 'The name can have at most 80 characters.';
    @TestVisible private static final String REFERRAL_MOBILE_INVALID = 'Enter a valid mobile number.';
    @TestVisible private static final String REFERRAL_NOT_A_CUSTOMER = 'Only customers can refer a friend.';
    @TestVisible private static final String REFERRAL_PROJECT_UNKNOWN = 'Choose a property from the list.';
    @TestVisible private static final String REFERRAL_NOT_SAVED = 'Your referral could not be sent right now. Please try again.';

    public class ReferralRecord {
        @AuraEnabled public String id;
        @AuraEnabled public String propertyName;
        @AuraEnabled public String friendName;
        @AuraEnabled public String emailId;
        @AuraEnabled public String mobileNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String referredOn;
        // Set once the lead has been converted: the opportunity it became and where that opportunity stands
        @AuraEnabled public Boolean isConverted;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String opportunityStage;
        @AuraEnabled public String opportunityAmount;
    }

    public class PropertyOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class ReferralSuccessData {
        @AuraEnabled public String heading;
        @AuraEnabled public String message;
        @AuraEnabled public String illustrationUrl;
    }

    public class ReferralPageData {
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String bannerImageUrl;
        @AuraEnabled public List<ReferralStep> referralSteps;
        @AuraEnabled public List<PropertyOption> propertyOptions;
        @AuraEnabled public List<ReferralRecord> referrals;
        @AuraEnabled public ReferralSuccessData successMessage;
    }

    // Not cacheable: the page reloads this right after a referral is sent, and a cached answer would still be the
    // list from before (the new card then only appeared after a full page refresh)
    @AuraEnabled
    public static ReferralPageData getReferralPageData() {
        ReferralPageData data = new ReferralPageData();

        data.title = 'Referrals';
        data.description = 'John Keells Properties  Referral Program is designed to help you earn some amazing rewards. Unlike most reward programs, we\u2019ve taken great care to ensure that the rewards you receive are in keeping with your fondness for life\u2019s finer indulgences. All you have to do is refer a friend or family member who is looking to invest in their dream property, and once their booking is confirmed, you will be rewarded with a 1% referral bonus on the property value. It really is that simple \u2014 share the opportunity, and let us take care of the rest.';

        data.bannerImageUrl = null;

        data.referralSteps = buildReferralSteps();
        data.propertyOptions = buildPropertyOptions();
        data.referrals = buildReferrals();
        data.successMessage = buildSuccessData();

        return data;
    }

    // "Refer Now": a Lead for the referred friend, owned by the Lead Assignment Queue, with this customer as
    // Referred By. LeadTrigger does the rest (normalised phone, the duplicate check of the lead chart, scoring).
    @AuraEnabled
    public static ReferralSuccessData sendReferral(String propertyName, String friendName, String mobileNumber) {
        String project = propertyName == null ? '' : propertyName.trim();
        String name = friendName == null ? '' : friendName.trim();
        String mobile = mobileNumber == null ? '' : mobileNumber.trim();
        if (String.isBlank(project) || String.isBlank(name) || String.isBlank(mobile)) {
            throw buildAuraException(REFERRAL_FIELDS_REQUIRED);
        }
        if (name.length() > 80) {
            throw buildAuraException(REFERRAL_NAME_TOO_LONG);
        }
        if (mobile.replaceAll('[^0-9]', '').length() < 9) {
            throw buildAuraException(REFERRAL_MOBILE_INVALID);
        }
        Id accountId = getCurrentAccountId();
        if (accountId == null) {
            throw buildAuraException(REFERRAL_NOT_A_CUSTOMER);
        }
        Id projectId = projectIdOf(project);
        if (projectId == null) {
            throw buildAuraException(REFERRAL_PROJECT_UNKNOWN);
        }
        Lead referred = new Lead(
            LastName = name,
            Company = name,
            Phone = mobile,
            Project__c = projectId,
            Referred_By__c = accountId,
            LeadSource = REFERRAL_LEAD_SOURCE,
            Status = REFERRAL_LEAD_STATUS,
            Lead_Classification__c = REFERRAL_CLASSIFICATION
        );
        Id queueId = leadAssignmentQueueId();
        if (queueId != null) {
            referred.OwnerId = queueId;
        }
        try {
            insert as system referred;
        } catch (DmlException e) {
            // The lead chart refuses a duplicate (same phone and project): the customer is told, nothing is created
            String reason = e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage();
            System.debug(LoggingLevel.INFO, 'Customer Portal referral refused: ' + reason);
            throw buildAuraException(String.isBlank(reason) ? REFERRAL_NOT_SAVED : reason);
        }
        return buildSuccessData();
    }

    // The project of the Refer Now list: its Id, or its name when an older page sends that
    private static Id projectIdOf(String project) {
        if (project instanceof Id || (project.length() == 15 || project.length() == 18)) {
            try {
                Id candidate = Id.valueOf(project);
                if (candidate.getSObjectType() == Project__c.SObjectType) {
                    return candidate;
                }
            } catch (Exception ignored) {
                // not an id: the name is tried below
            }
        }
        for (Project__c found : [
            SELECT Id FROM Project__c WHERE Name = :project AND Active__c = true WITH SYSTEM_MODE LIMIT 1
        ]) {
            return found.Id;
        }
        return null;
    }

    private static Id leadAssignmentQueueId() {
        for (Group queue : [
            SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :LEAD_QUEUE WITH SYSTEM_MODE LIMIT 1
        ]) {
            return queue.Id;
        }
        return null;
    }

    private static List<ReferralStep> buildReferralSteps() {
        List<ReferralStep> steps = new List<ReferralStep>();

        steps.add(buildStep(1, 'Invite\nA Referral', null, null, 'utility:add_contact'));
        steps.add(buildStep(2, 'Referral to Accept', null, null, 'utility:like'));
        steps.add(buildStep(3, 'Check Referral Status', null, null, 'utility:task'));
        steps.add(buildStep(4, 'On Referral Booking Confirmation\nComes The Reward !!!', null, null, 'utility:favorite'));

        return steps;
    }

    private static ReferralStep buildStep(Integer stepNumber, String title, String description, String imageUrl, String iconName) {
        ReferralStep step = new ReferralStep();
        step.stepNumber = stepNumber;
        step.title = title;
        step.description = description;
        step.imageUrl = imageUrl;
        step.iconName = iconName;
        return step;
    }

    // Every active project, as the Refer Now list
    private static List<PropertyOption> buildPropertyOptions() {
        List<PropertyOption> options = new List<PropertyOption>();
        for (Project__c project : [
            SELECT Id, Name FROM Project__c WHERE Active__c = true WITH SYSTEM_MODE ORDER BY Name
        ]) {
            options.add(buildOption(project.Name, project.Id));
        }
        return options;
    }

    private static PropertyOption buildOption(String label, String value) {
        PropertyOption opt = new PropertyOption();
        opt.label = label;
        opt.value = value;
        return opt;
    }

    // The leads this customer referred, newest first, with the opportunity when one of them was converted
    private static List<ReferralRecord> buildReferrals() {
        List<ReferralRecord> referrals = new List<ReferralRecord>();
        Id accountId = getCurrentAccountId();
        if (accountId == null) {
            return referrals;
        }
        List<Lead> leads = [
            SELECT Id, Name, Email, Phone, MobilePhone, Status, CreatedDate, Project__r.Name,
                IsConverted, ConvertedOpportunityId
            FROM Lead
            WHERE Referred_By__c = :accountId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
        Set<Id> opportunityIds = new Set<Id>();
        for (Lead referred : leads) {
            if (referred.ConvertedOpportunityId != null) {
                opportunityIds.add(referred.ConvertedOpportunityId);
            }
        }
        Map<Id, Opportunity> opportunities = opportunityIds.isEmpty()
            ? new Map<Id, Opportunity>()
            : new Map<Id, Opportunity>([
                SELECT Id, Name, StageName, Amount FROM Opportunity WHERE Id IN :opportunityIds WITH SYSTEM_MODE
            ]);
        for (Lead referred : leads) {
            ReferralRecord record = new ReferralRecord();
            record.id = referred.Id;
            record.friendName = referred.Name;
            record.emailId = referred.Email;
            record.mobileNumber = String.isNotBlank(referred.Phone) ? referred.Phone : referred.MobilePhone;
            record.propertyName = referred.Project__r == null ? '' : referred.Project__r.Name;
            record.status = referred.Status;
            record.referredOn = referred.CreatedDate == null ? '' : referred.CreatedDate.format('dd MMM yyyy');
            record.isConverted = referred.IsConverted;
            Opportunity booking = opportunities.get(referred.ConvertedOpportunityId);
            if (booking != null) {
                record.opportunityName = booking.Name;
                record.opportunityStage = booking.StageName;
                record.opportunityAmount = booking.Amount == null ? null : fmtMoney(booking.Amount);
            }
            referrals.add(record);
        }
        return referrals;
    }

    private static ReferralRecord buildReferral(String id, String propertyName, String friendName, String emailId, String mobileNumber, String status) {
        ReferralRecord rec = new ReferralRecord();
        rec.id = id;
        rec.propertyName = propertyName;
        rec.friendName = friendName;
        rec.emailId = emailId;
        rec.mobileNumber = mobileNumber;
        rec.status = status;
        return rec;
    }

    private static ReferralSuccessData buildSuccessData() {
        ReferralSuccessData success = new ReferralSuccessData();
        success.heading = 'Your referral was sent!';
        success.message = 'Congratulations! Your referral has been successfully submitted. We appreciate your support in recommending John Keells Properties . to others. Should you have any questions or need further assistance, please don\u2019t hesitate to contact us.';
        success.illustrationUrl = '/resource/ReferralSuccessIllustration';
        return success;
    }

     public class BankDetails {
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountNo;
        @AuraEnabled public String bankName;
        @AuraEnabled public String branchName;
        @AuraEnabled public String swiftCode;
    }
 
    public class BookingDetail {
        @AuraEnabled public String id;
        @AuraEnabled public String description;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public String carParks;
        @AuraEnabled public String type;
        @AuraEnabled public String spaDate;
        @AuraEnabled public String flatVilla;
        @AuraEnabled public String towerBlockVilla;
        @AuraEnabled public String squareFeet;
        @AuraEnabled public String purchasedPrice;
        @AuraEnabled public String escrowAccountNumber;
        @AuraEnabled public BankDetails bankDetails;
    }
 
    public class PaymentPlanRow {
        @AuraEnabled public String description;
        @AuraEnabled public String percentage;
        @AuraEnabled public String trancheDate;
        @AuraEnabled public String amount;
    }
 
    public class Applicant {
        @AuraEnabled public String name;
        @AuraEnabled public String applicantType; 
        @AuraEnabled public String avatar;        
        @AuraEnabled public String dateOfBirth;
        @AuraEnabled public String mobileNumber;
        @AuraEnabled public String email;
        @AuraEnabled public String address;
        @AuraEnabled public String nic;
        @AuraEnabled public String tin;
        @AuraEnabled public String passport;
        @AuraEnabled public String companyName;
        @AuraEnabled public String vatNumber;
        @AuraEnabled public String businessRegistrationNumber;
    }
 
    public class MyProperty {
        @AuraEnabled public String id;
        @AuraEnabled public String projectName;
        @AuraEnabled public String projectId;
        @AuraEnabled public String description;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public String carParks;
        @AuraEnabled public String type;
        @AuraEnabled public List<Applicant> applicants;
        @AuraEnabled public List<BookingDetail> bookingDetails;
        @AuraEnabled public List<PaymentPlanRow> paymentPlan;
        @AuraEnabled public String paymentPlanTotal;
    }
 
    public class MyPropertiesPageData {
        @AuraEnabled public String pageTitle;
        @AuraEnabled public String description;
        @AuraEnabled public List<PropertyOption> projectFilters;
        @AuraEnabled public List<MyProperty> properties;
    }
 
   @AuraEnabled(cacheable=true)
    public static MyPropertiesPageData getMyProperties() {
        MyPropertiesPageData data = new MyPropertiesPageData();
        data.pageTitle = 'My Properties';
        data.description = 'Easily manage your property bookings with John Keels Properties . View your current reservations, check the status of your applications, and stay updated on the next steps. Our dedicated team is here to ensure a smooth and hassle-free booking experience. For any assistance, feel free to contact our support team anytime.';
        data.projectFilters = new List<PropertyOption>();
        data.properties = new List<MyProperty>();

        Id accountId = getCurrentAccountId();
        if (accountId == null) return data;

        Set<Id> unitIds = new Set<Id>();
        for (Opportunity o : [SELECT Unit__c FROM Opportunity WHERE AccountId = :accountId AND Unit__c != null WITH SYSTEM_MODE]) {
            unitIds.add(o.Unit__c);
        }
        if (unitIds.isEmpty()) return data;

        Map<Id, String> projectNames = new Map<Id, String>();
        for (Unit__c u : [SELECT Id, Unit_Name_Code__c, Unit_Type__c, Default_Parking__c,Floor__r.Block__r.Project__c, Floor__r.Block__r.Project__r.Name FROM Unit__c WHERE Id IN :unitIds WITH SYSTEM_MODE ORDER BY Unit_Name_Code__c]) {
            Project__c prj = (u.Floor__r != null && u.Floor__r.Block__r != null)? u.Floor__r.Block__r.Project__r : null;

            MyProperty p = new MyProperty();
            p.id          = u.Id;                      
            p.projectId   = prj != null ? prj.Id : null; 
            p.projectName = prj != null ? prj.Name : '';
            p.description = p.projectName;
            p.unitNumber  = u.Unit_Name_Code__c;
            p.carParks    = u.Default_Parking__c != null ? String.valueOf(u.Default_Parking__c) : '';
            p.type        = picklistLabel(Unit__c.Unit_Type__c, u.Unit_Type__c);
            data.properties.add(p);

            if (prj != null && !projectNames.containsKey(prj.Id)) {
                projectNames.put(prj.Id, prj.Name);
                data.projectFilters.add(buildOption(prj.Name, String.valueOf(prj.Id)));
            }
        }
        return data;
    }

    @AuraEnabled(cacheable=true)
    public static MyProperty getMyPropertyDetails(String propertyId) {
        Id accountId = getCurrentAccountId();
        if (accountId == null || String.isBlank(propertyId)) {
            throw buildAuraException('Property not found.');
        }

        List<Opportunity> opps = [SELECT Id, SPA_Signed_Date__c, Amount FROM Opportunity WHERE Unit__c = :propertyId AND AccountId = :accountId WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1];
        if (opps.isEmpty()) throw buildAuraException('Property not found.');
        Opportunity opp = opps[0];

        Unit__c unit = [SELECT Id, Unit_Name_Code__c, Unit_Type__c, Salable_Area_sqft__c,Default_Parking__c, Floor__r.Block__r.Name FROM Unit__c WHERE Id = :propertyId WITH SYSTEM_MODE LIMIT 1];

        MyProperty prop = new MyProperty();
        prop.id = unit.Id;

        prop.applicants = new List<Applicant>();
        Integer pos = 0;
        for (Applicant__c ap : [SELECT Name, Account__r.Name, Account__r.Phone, Account__r.Email__c,Account__r.ShippingStreet, Account__r.ShippingCity,Account__r.ShippingCountry,Account__r.TIN_Tax_Identification_Number__c, Account__r.Passport__c FROM Applicant__c WHERE Opportunity__c = :opp.Id WITH SYSTEM_MODE ORDER BY CreatedDate ASC]) {
            Applicant a = new Applicant();
            a.name          = ap.Account__r.Name;
            a.applicantType = ordinal(pos++) + ' Applicant';
            a.mobileNumber  = ap.Account__r.Phone;
            a.email         = ap.Account__r.Email__c;
            a.address       = joinNonBlank(new List<String>{ ap.Account__r.ShippingStreet,ap.Account__r.ShippingCity, ap.Account__r.ShippingCountry });
            a.tin           = ap.Account__r.TIN_Tax_Identification_Number__c;
            a.passport      = ap.Account__r.Passport__c;
            prop.applicants.add(a);
        }

        prop.paymentPlan = new List<PaymentPlanRow>();
        Decimal total = 0;
        for (Cost_Sheet_Payment_Schedule__c s : [SELECT Description__c, Installment__c, Pay_Date__c, Due_Date__c,Total_Amount_Inclusive_Of_Tax__c FROM Cost_Sheet_Payment_Schedule__c WHERE Opportunity__c = :opp.Id WITH SYSTEM_MODE ORDER BY Installment_Sequence__c ASC NULLS LAST, CreatedDate ASC]) {
            PaymentPlanRow r = new PaymentPlanRow();
            r.description = s.Description__c;
            r.percentage  = s.Installment__c != null ? String.valueOf(s.Installment__c) : '';
            r.trancheDate = fmtDate(s.Due_Date__c != null ? s.Due_Date__c : s.Pay_Date__c);
            r.amount      = fmtMoney(s.Total_Amount_Inclusive_Of_Tax__c);
            prop.paymentPlan.add(r);
            total += s.Total_Amount_Inclusive_Of_Tax__c != null ? s.Total_Amount_Inclusive_Of_Tax__c : 0;
        }
        prop.paymentPlanTotal = fmtMoney(total);

        List<Escrow_Account__c> escrow = [SELECT Name FROM Escrow_Account__c WHERE (Unit__c = :unit.Id OR Opportunity__c = :opp.Id) AND Status__c = true WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1];

        BookingDetail b = new BookingDetail();
        b.id                  = unit.Id;
        b.unitNumber          = unit.Unit_Name_Code__c;
        b.carParks            = unit.Default_Parking__c != null ? String.valueOf(unit.Default_Parking__c) : '';
        b.type                = picklistLabel(Unit__c.Unit_Type__c, unit.Unit_Type__c);
        b.spaDate             = fmtDate(opp.SPA_Signed_Date__c);
        b.towerBlockVilla     = unit.Floor__r.Block__r.Name;
        b.squareFeet          = unit.Salable_Area_sqft__c != null ? String.valueOf(unit.Salable_Area_sqft__c) : '';
        b.purchasedPrice      = fmtMoney(total > 0 ? total : opp.Amount);
        b.escrowAccountNumber = escrow.isEmpty() ? '' : escrow[0].Name;
        b.bankDetails         = new BankDetails();   // no source in the APIs yet, see gaps below
        prop.bookingDetails   = new List<BookingDetail>{ b };
        return prop;
    }

    private static Id getCurrentAccountId() {
        List<User> us = [SELECT Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return (us.isEmpty() || us[0].Contact == null) ? null : us[0].Contact.AccountId;
    }
    private static String fmtDate(Date d) {
        return d == null ? '' : Datetime.newInstance(d, Time.newInstance(0,0,0,0)).format('dd/MM/yyyy');
    }
    private static String fmtMoney(Decimal v) {
        return v == null ? '' : 'LKR ' + v.setScale(2, RoundingMode.HALF_UP).format();
    }
    private static String ordinal(Integer i) {
        List<String> w = new List<String>{'First','Second','Third','Fourth','Fifth'};
        return i < w.size() ? w[i] : String.valueOf(i + 1) + 'th';
    }
    private static String picklistLabel(Schema.SObjectField f, String v) {
        for (Schema.PicklistEntry e : f.getDescribe().getPicklistValues()) {
            if (e.getValue() == v) return e.getLabel();
        }
        return v;
    }
    private static String joinNonBlank(List<String> parts) {
        List<String> out = new List<String>();
        for (String s : parts) if (String.isNotBlank(s)) out.add(s);
        return String.join(out, ', ');
    }
 

   public class ConstructionImage {
        @AuraEnabled public String id;
        @AuraEnabled public String imageUrl;
    }

    public class ConstructionVideo {
        @AuraEnabled public String id;
        @AuraEnabled public String thumbnailUrl;
        @AuraEnabled public String videoUrl;
    }

    public class ConstructionUpdate {
        @AuraEnabled public String id;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public List<ConstructionImage> images;
        @AuraEnabled public List<ConstructionVideo> videos;
    }

    public class ConstructionProject {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public List<ConstructionImage> images;
        @AuraEnabled public Integer progress; // 0-100
        @AuraEnabled public List<ConstructionUpdate> updates;
    }

    public class ConstructionStatusPageData {
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public List<ConstructionProject> projects;
    }

    @AuraEnabled(cacheable=true)
    public static ConstructionStatusPageData getConstructionStatus() {
        ConstructionStatusPageData data = new ConstructionStatusPageData();

        data.title = 'Construction Status';
        data.description = 'Stay updated with John Keels Properties\'s latest project developments. Track the progress of your project, receive timely updates on milestones, and stay informed about upcoming phases. Our team is dedicated to providing you with transparent and regular project updates. For any inquiries or further information, please contact our support team.';

        data.projects = buildConstructionProjects();

        return data;
    }

    private static List<ConstructionProject> buildConstructionProjects() {
        List<ConstructionProject> projects = new List<ConstructionProject>();

        projects.add(buildConstructionProject(
            'CONST-001',
            'JK Kingsland',
            'B2-210',
            new List<String>{
                'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=900',
                'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=900',
                'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=900'
            },
            51
        ));

        projects.add(buildConstructionProject(
            'CONST-002',
            'JK Pallaciya',
            'B2-210',
            new List<String>{
                'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=900',
                'https://images.unsplash.com/photo-1571055107559-3e67626fa8be?w=900',
                'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00?w=900'
            },
            71
        ));

        return projects;
    }

    private static ConstructionProject buildConstructionProject(String id,String name,String unitNumber,List<String> imageUrls,Integer progress) {
        ConstructionProject p = new ConstructionProject();
        p.id = id;
        p.name = name;
        p.unitNumber = unitNumber;
        p.progress = progress;

        p.images = new List<ConstructionImage>();
        Integer idx = 1;
        for (String url : imageUrls) {
            ConstructionImage img = new ConstructionImage();
            img.id = id + '-CARD-IMG-' + idx;
            img.imageUrl = url;
            p.images.add(img);
            idx++;
        }

        p.updates = buildConstructionUpdates(id);
        return p;
    }

    private static List<ConstructionUpdate> buildConstructionUpdates(String projectId) {
        List<ConstructionUpdate> updates = new List<ConstructionUpdate>();

        updates.add(buildConstructionUpdate(
            projectId + '-JUN2024',
            'June 2024 Updates',
            new List<String>{
                'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=600',
                'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=600',
                'https://images.unsplash.com/photo-1449844908441-8829872d2607?w=600',
                'https://images.unsplash.com/photo-1600047509807-ba8f99d2cdde?w=600',
                'https://images.unsplash.com/photo-1502005229762-cf1b2da7c5d6?w=600',
                'https://images.unsplash.com/photo-1523217582562-09d0def993a6?w=600',
                'https://images.unsplash.com/photo-1494526585095-c41746248156?w=600',
                'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=600',
                'https://images.unsplash.com/photo-1580587771525-78b9dba3b914?w=600',
                'https://images.unsplash.com/photo-1580216643062-cf460548a66a?w=600',
                'https://images.unsplash.com/photo-1570129477492-45c003edd2be?w=600'
            },
            new List<String[]>{
                new String[]{ 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=400', 'https://www.w3schools.com/html/mov_bbb.mp4' },
                new String[]{ 'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=400', 'https://www.w3schools.com/html/movie.mp4' }
            }
        ));

        updates.add(buildConstructionUpdate(
            projectId + '-MAY2024',
            'May 2024 Updates',
            new List<String>{
                'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=600',
                'https://images.unsplash.com/photo-1571055107559-3e67626fa8be?w=600',
                'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00?w=600'
            },
            new List<String[]>{
                new String[]{ 'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=400', 'https://www.w3schools.com/html/mov_bbb.mp4' }
            }
        ));

        updates.add(buildConstructionUpdate(
            projectId + '-APR2024',
            'April 2024 Updates',
            new List<String>{
                'https://images.unsplash.com/photo-1580587771525-78b9dba3b914?w=600',
                'https://images.unsplash.com/photo-1580216643062-cf460548a66a?w=600'
            },
            new List<String[]>()
        ));

        updates.add(buildConstructionUpdate(
            projectId + '-MAR2024',
            'March 2024 Updates',
            new List<String>{
                'https://images.unsplash.com/photo-1494526585095-c41746248156?w=600'
            },
            new List<String[]>()
        ));

        return updates;
    }

    private static ConstructionUpdate buildConstructionUpdate(String id,String monthLabel,List<String> imageUrls,List<String[]> videoPairs) {
        ConstructionUpdate u = new ConstructionUpdate();
        u.id = id;
        u.monthLabel = monthLabel;

        u.images = new List<ConstructionImage>();
        Integer idx = 1;
        for (String url : imageUrls) {
            ConstructionImage img = new ConstructionImage();
            img.id = id + '-IMG-' + idx;
            img.imageUrl = url;
            u.images.add(img);
            idx++;
        }

        u.videos = new List<ConstructionVideo>();
        idx = 1;
        for (String[] pair : videoPairs) {
            ConstructionVideo vid = new ConstructionVideo();
            vid.id = id + '-VID-' + idx;
            vid.thumbnailUrl = pair[0];
            vid.videoUrl = pair[1];
            u.videos.add(vid);
            idx++;
        }

        return u;
    }

        
    public class AccountImage {
        @AuraEnabled public String url;
        @AuraEnabled public Integer displayOrder;
    }
    
    public class MyAccountCard {
        @AuraEnabled public String id;
        @AuraEnabled public String projectName;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public String filterValue;
        @AuraEnabled public List<AccountImage> images;
    }
    
    public class AccountSummary {
        @AuraEnabled public String totalValueBilled;
        @AuraEnabled public String totalAmountPaid;
        @AuraEnabled public String totalAmountDue;
        @AuraEnabled public String percentagePaid;
        @AuraEnabled public String totalInterestAccumulated;
        @AuraEnabled public String customisationCharges;
        @AuraEnabled public String purchasedPrice;
        @AuraEnabled public String totalPayable;
        @AuraEnabled public String downloadUrl;
    }
    
    public class PayableItem {
        @AuraEnabled public String id;
        @AuraEnabled public String type;
        @AuraEnabled public String amount;
        @AuraEnabled public String status;
        @AuraEnabled public String dueDate;
        @AuraEnabled public String description;
        @AuraEnabled public String details;
    }
    
    public class MyAccountDetails {
        @AuraEnabled public String id;
        @AuraEnabled public String projectName;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public AccountSummary accountSummary;
        @AuraEnabled public List<PayableItem> payables;
    }
    
    public class MyAccountsPageData {
        @AuraEnabled public String pageTitle;
        @AuraEnabled public String description;
        @AuraEnabled public List<PropertyOption> projectFilters;
        @AuraEnabled public List<MyAccountCard> accounts;
    }
    
    
    @AuraEnabled(cacheable=true)
    public static MyAccountsPageData getMyAccountsPageData() {
        MyAccountsPageData data = new MyAccountsPageData();
    
        data.pageTitle = 'Accounts';
        data.description = 'Access and manage your customer documents with John Keels Properties below. '
            + 'Stay informed on contracts, agreements, and customer records securely. Our platform ensures '
            + 'easy navigation and secure document handling. For any questions or additional assistance, '
            + 'please don\u2019t hesitate to contact our support team.';
    
        data.projectFilters = new List<PropertyOption>{
            buildOption('JK Kingsland', 'JK Kingsland'),
            buildOption('JK Pallaciya', 'JK Pallaciya'),
            buildOption('The Monarch', 'The Monarch')
        };
    
        data.accounts = buildMyAccountCards();
    
        return data;
    }
    
    @AuraEnabled(cacheable=true)
    public static MyAccountDetails getMyAccountDetails(String accountId) {
        Map<String, MyAccountDetails> detailsById = buildMyAccountDetailsMap();
    
        if (detailsById.containsKey(accountId)) {
            return detailsById.get(accountId);
        }
    
        return detailsById.values()[0];
    }
    
    
    private static List<MyAccountCard> buildMyAccountCards() {
        List<MyAccountCard> cards = new List<MyAccountCard>();
    
        cards.add(buildAccountCard(
            'ACC-001',
            'JK Kingsland',
            'B2-210',
            'JK Kingsland',
            new List<String>{
                'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800',
                'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=800',
                'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=800',
                'https://images.unsplash.com/photo-1523217582562-09d0def993a6?w=800'
            }
        ));
    
        cards.add(buildAccountCard(
            'ACC-002',
            'JK Pallaciya',
            'B2-210',
            'JK Pallaciya',
            new List<String>{
                'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=800',
                'https://images.unsplash.com/photo-1571055107559-3e67626fa8be?w=800',
                'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00?w=800'
            }
        ));
    
        cards.add(buildAccountCard(
            'ACC-003',
            'The Monarch',
            'A1-104',
            'The Monarch',
            new List<String>{
                'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=800',
                'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=800'
            }
        ));
    
        return cards;
    }
    
    private static MyAccountCard buildAccountCard(String id, String projectName, String unitNumber, String filterValue, List<String> imageUrls) {
        MyAccountCard card = new MyAccountCard();
        card.id = id;
        card.projectName = projectName;
        card.unitNumber = unitNumber;
        card.filterValue = filterValue;
    
        card.images = new List<AccountImage>();
        Integer order = 1;
        for (String url : imageUrls) {
            AccountImage img = new AccountImage();
            img.url = url;
            img.displayOrder = order;
            card.images.add(img);
            order++;
        }
    
        return card;
    }
    
    private static Map<String, MyAccountDetails> buildMyAccountDetailsMap() {
        Map<String, MyAccountDetails> result = new Map<String, MyAccountDetails>();
    
        result.put('ACC-001', buildAccountDetails(
            'ACC-001', 'JK Kingsland', 'B2-210',
            'LKR 5,475,399', 'LKR 5,444,291', 'LKR 31,553', '10%',
            'LKR 658', 'LKR 1,043,278', 'LKR 16,285,130', 'LKR 32,210',
            buildPayablesForAccount('ACC-001')
        ));
    
        result.put('ACC-002', buildAccountDetails(
            'ACC-002', 'JK Pallaciya', 'B2-210',
            'LKR 4,120,000', 'LKR 3,980,500', 'LKR 139,500', '96%',
            'LKR 1,240', 'LKR 620,000', 'LKR 12,450,000', 'LKR 145,000',
            buildPayablesForAccount('ACC-002')
        ));
    
        result.put('ACC-003', buildAccountDetails(
            'ACC-003', 'The Monarch', 'A1-104',
            'LKR 5,475,399', 'LKR 5,444,291', 'LKR 31,553', '10%',
            'LKR 658', 'LKR 1,043,278', 'LKR 16,285,130', 'LKR 32,210',
            buildPayablesForAccount('ACC-003')
        ));
    
        return result;
    }
    
    private static MyAccountDetails buildAccountDetails(
        String id, String projectName, String unitNumber,
        String totalValueBilled, String totalAmountPaid, String totalAmountDue, String percentagePaid,
        String totalInterestAccumulated, String customisationCharges, String purchasedPrice, String totalPayable,
        List<PayableItem> payables
    ) {
        MyAccountDetails details = new MyAccountDetails();
        details.id = id;
        details.projectName = projectName;
        details.unitNumber = unitNumber;
    
        AccountSummary summary = new AccountSummary();
        summary.totalValueBilled = totalValueBilled;
        summary.totalAmountPaid = totalAmountPaid;
        summary.totalAmountDue = totalAmountDue;
        summary.percentagePaid = percentagePaid;
        summary.totalInterestAccumulated = totalInterestAccumulated;
        summary.customisationCharges = customisationCharges;
        summary.purchasedPrice = purchasedPrice;
        summary.totalPayable = totalPayable;
        summary.downloadUrl = null; 
        details.accountSummary = summary;
    
        details.payables = payables;
    
        return details;
    }
    
    private static List<PayableItem> buildPayablesForAccount(String accountId) {
        List<PayableItem> payables = new List<PayableItem>();
    
        payables.add(buildPayable(
            accountId + '-PAY-1', 'Utility Charge', 'LKR 32,210', 'Pending', '30/09/2026',
            'Utility charge', 'Covers water, electricity and common-area utility costs billed for the current period.'
        ));
    
        payables.add(buildPayable(
            accountId + '-PAY-2', 'ACT Charge', 'LKR 32,210', 'Pending', '30/09/2026',
            'Association / common-area transformer charge', 'Applicable common facility transformer charge for the billing cycle.'
        ));
    
        payables.add(buildPayable(
            accountId + '-PAY-3', 'Insurance', 'LKR 32,210', 'Pending', '30/09/2026',
            'Property insurance premium', 'Annual insurance premium covering the unit against fire and structural damage.'
        ));
    
        return payables;
    }
    
    private static PayableItem buildPayable(String id, String type, String amount, String status, String dueDate, String description, String details) {
        PayableItem item = new PayableItem();
        item.id = id;
        item.type = type;
        item.amount = amount;
        item.status = status;
        item.dueDate = dueDate;
        item.description = description;
        item.details = details;
        return item;
    }


    public class VisitImage {
        @AuraEnabled public String url;
        @AuraEnabled public Integer displayOrder;
    }

    public class Visit {
        @AuraEnabled public String id;
        @AuraEnabled public String projectName;
        @AuraEnabled public String address;             
        @AuraEnabled public String correspondenceAddress;  
        @AuraEnabled public String location;
        @AuraEnabled public String propertyType;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public String customerId;
        @AuraEnabled public String bookingId;
        @AuraEnabled public String visitDate;
        @AuraEnabled public String visitTime;
        @AuraEnabled public String completedDate;
        @AuraEnabled public String completedTime;
        @AuraEnabled public String cancelledDate;
        @AuraEnabled public String cancelledTime;
        @AuraEnabled public String crmHandoverPerson;
        @AuraEnabled public String comments;
        @AuraEnabled public List<VisitImage> images;
        @AuraEnabled public String status; 
    }

    public class FeedbackQuestion {
        @AuraEnabled public String id;
        @AuraEnabled public Integer questionNumber;
        @AuraEnabled public String text;
    }

    public class MyVisitsPageData {
        @AuraEnabled public String pageTitle;
        @AuraEnabled public String description;
        @AuraEnabled public List<Visit> upcomingVisits;
        @AuraEnabled public List<Visit> completedVisits;
        @AuraEnabled public List<Visit> incompleteVisits;
        @AuraEnabled public List<PropertyOption> scheduleVisitOptions;
        @AuraEnabled public List<PropertyOption> scheduleUnitOptions;  
        @AuraEnabled public List<PropertyOption> visitTypeOptions;
        @AuraEnabled public List<PropertyOption> rescheduleReasons;
        @AuraEnabled public List<FeedbackQuestion> feedbackQuestions;
    }

    public class VisitActionResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public String visitId;
    }

    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    @AuraEnabled(cacheable=true)
    public static MyVisitsPageData getMyVisitsPageData() {
        try {
            MyVisitsPageData data = new MyVisitsPageData();

            data.pageTitle = 'Visits for Handover';
            data.description = 'Schedule and manage your site visits effortlessly with John Keels Properties . '
                + 'Stay updated on your visit appointments, access location details, and receive reminders for '
                + 'upcoming visits. Our team is dedicated to providing you with a smooth and informative site '
                + 'visit experience. For any questions or additional assistance, please don\u2019t hesitate to '
                + 'contact our support team.';

            data.upcomingVisits = new List<Visit>{ buildUpcomingVisit() };
            data.completedVisits = new List<Visit>{ buildCompletedVisit() };
            data.incompleteVisits = new List<Visit>{ buildIncompleteVisit() };

            data.scheduleVisitOptions = new List<PropertyOption>{
                buildOption('JK Kingsland', 'JK Kingsland'),
                buildOption('JK Pallaciya', 'JK Pallaciya'),
                buildOption('The Monarch', 'The Monarch')
            };

            data.scheduleUnitOptions = new List<PropertyOption>{
                buildOption('B2-210', 'B2-210'),
                buildOption('A1-104', 'A1-104'),
                buildOption('C3-310', 'C3-310')
            };

            data.visitTypeOptions = new List<PropertyOption>{
                buildOption('Site Visit', 'Site Visit'),
                buildOption('Virtual Visit', 'Virtual Visit'),
                buildOption('Handover Visit', 'Handover Visit')
            };

            data.rescheduleReasons = new List<PropertyOption>{
                buildOption('Personal Reasons', 'Personal Reasons'),
                buildOption('Travel', 'Travel'),
                buildOption('Schedule Conflict', 'Schedule Conflict'),
                buildOption('Emergency', 'Emergency'),
                buildOption('Others', 'Others')
            };

            data.feedbackQuestions = buildFeedbackQuestions();

            return data;
        } catch (Exception e) {
            throw buildAuraException('Unable to load your visits: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static VisitActionResponse scheduleVisit(String projectName, String unitNumber, String visitDate, String visitTime, String visitType, String visitDetails) {
        if (String.isBlank(projectName) || String.isBlank(unitNumber) || String.isBlank(visitDate)
            || String.isBlank(visitTime) || String.isBlank(visitType)) {
            throw buildAuraException('Property, unit, date, time and visit type are required.');
        }

        try {
            // insert new Site_Visit__c(
            //     Project__c = projectName,
            //     Unit_Number__c = unitNumber,
            //     Visit_Date__c = Date.valueOf(visitDate),
            //     Visit_Time__c = visitTime,
            //     Visit_Type__c = visitType,
            //     Visit_Details__c = visitDetails,
            //     Status__c = 'Upcoming'
            // );

            VisitActionResponse response = new VisitActionResponse();
            response.success = true;
            response.title = 'Your site visit has been scheduled!';
            response.message = 'Your site visit to ' + projectName + ' (' + unitNumber + ') has been scheduled for '
                + visitDate + ' at ' + visitTime + '. We look forward to showing you the property. If you have any '
                + 'questions or need further assistance, please don\u2019t hesitate to contact us.';
            response.visitId = null;
            return response;
        } catch (Exception e) {
            throw buildAuraException('Unable to schedule the visit: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static VisitActionResponse rescheduleVisit(String visitId, String property, String visitDate, String visitTime, String reason, String visitDetails) {
        if (String.isBlank(visitId) || String.isBlank(visitDate) || String.isBlank(visitTime) || String.isBlank(reason)) {
            throw buildAuraException('Visit, date, time and reason are required.');
        }

        try {
            // update new Site_Visit__c(
            //     Id = visitId,
            //     Visit_Date__c = Date.valueOf(visitDate),
            //     Visit_Time__c = visitTime,
            //     Reschedule_Reason__c = reason,
            //     Visit_Details__c = visitDetails
            // );

            VisitActionResponse response = new VisitActionResponse();
            response.success = true;
            response.title = 'Your site visit has been rescheduled!';
            response.message = 'Your site visit to ' + property + ' has been rescheduled to ' + visitDate
                + ' at ' + visitTime + '. We look forward to showing you the property on the new date. '
                + 'If you have any questions or need further assistance, please don\u2019t hesitate to '
                + 'contact us.';
            response.visitId = visitId;
            return response;
        } catch (Exception e) {
            throw buildAuraException('Unable to reschedule the visit: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static VisitActionResponse cancelVisit(String visitId, String projectName, String cancellationReason) {
        if (String.isBlank(visitId) || String.isBlank(cancellationReason)) {
            throw buildAuraException('Visit and cancellation reason are required.');
        }

        try {
            // update new Site_Visit__c(
            //     Id = visitId,
            //     Status__c = 'Cancelled',
            //     Cancellation_Reason__c = cancellationReason
            // );

            VisitActionResponse response = new VisitActionResponse();
            response.success = true;
            response.title = 'Your site visit has been cancelled!';
            response.message = 'Your site visit to ' + projectName + ' has been cancelled. We apologize if '
                + 'any inconvenience caused. If you have any questions or need further assistance, please '
                + 'don\u2019t hesitate to contact us.';
            response.visitId = visitId;
            return response;
        } catch (Exception e) {
            throw buildAuraException('Unable to cancel the visit: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static VisitActionResponse submitVisitFeedback(String visitId, Integer rating1, Integer rating2, Integer rating3, Integer rating4, Integer rating5) {
        if (String.isBlank(visitId) || rating1 == null || rating2 == null || rating3 == null || rating4 == null || rating5 == null) {
            throw buildAuraException('Visit and all five ratings are required.');
        }

        try {
            // insert new Visit_Feedback__c(
            //     Visit__c = visitId,
            //     Rating_1__c = rating1,
            //     Rating_2__c = rating2,
            //     Rating_3__c = rating3,
            //     Rating_4__c = rating4,
            //     Rating_5__c = rating5
            // );

            VisitActionResponse response = new VisitActionResponse();
            response.success = true;
            response.title = 'Thanks for your Feedback!';
            response.message = 'Thank you for sharing your feedback with John Keels Properties . Your input '
                + 'helps us enhance our services to better meet your needs. We appreciate your valuable '
                + 'contribution!';
            response.visitId = visitId;
            return response;
        } catch (Exception e) {
            throw buildAuraException('Unable to submit your feedback: ' + e.getMessage());
        }
    }

    private static List<FeedbackQuestion> buildFeedbackQuestions() {
        List<FeedbackQuestion> questions = new List<FeedbackQuestion>();

        questions.add(buildFeedbackQuestion('q1', 1, 'How would you rate the overall condition and appearance of the property?'));
        questions.add(buildFeedbackQuestion('q2', 2, 'Did the property meet your expectations based on the listing?'));
        questions.add(buildFeedbackQuestion('q3', 3, 'Were you satisfied with the location and neighborhood?'));
        questions.add(buildFeedbackQuestion('q4', 4, 'Were your questions and concerns addressed adequately during the visit?'));
        questions.add(buildFeedbackQuestion('q5', 5, 'How likely are you to consider this property further or recommend it to others based on your visit experience?'));

        return questions;
    }

    private static FeedbackQuestion buildFeedbackQuestion(String id, Integer questionNumber, String text) {
        FeedbackQuestion q = new FeedbackQuestion();
        q.id = id;
        q.questionNumber = questionNumber;
        q.text = text;
        return q;
    }

    private static Visit buildUpcomingVisit() {
        Visit v = buildBaseVisit('VISIT-001');
        v.status = 'Upcoming';
        return v;
    }

    private static Visit buildCompletedVisit() {
        Visit v = buildBaseVisit('VISIT-002');
        v.status = 'Completed';
        v.completedDate = '24/5/2023, Wednesday';
        v.completedTime = '11:00 AM';
        v.comments = '';
        return v;
    }

    private static Visit buildIncompleteVisit() {
        Visit v = buildBaseVisit('VISIT-003');
        v.status = 'Incomplete';
        v.cancelledDate = '24/5/2023, Wednesday';
        v.cancelledTime = '11:00 AM';
        v.comments = '';
        return v;
    }

    private static Visit buildBaseVisit(String id) {
        Visit v = new Visit();
        v.id = id;
        v.projectName = 'JK Kingsland';
        v.address = 'Plot No-15, VIP Colony, Nayapally, Bhubaneswar';
        v.correspondenceAddress = 'John Keels Properties, No 186, Vauxhall Street, Colombo, Sri Lanka.';
        v.location = 'Colombo';
        v.propertyType = '3 & 4 BHK';
        v.unitNumber = '7B-B3-310';
        v.customerId = 'CUST12345';
        v.bookingId = '0090';
        v.visitDate = '24/5/2023, Wednesday';
        v.visitTime = '11:00 AM';
        v.crmHandoverPerson = 'Manoj Desai';

        v.images = new List<VisitImage>();
        List<String> imageUrls = new List<String>{
            'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800',
            'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=800',
            'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=800'
        };
        Integer order = 1;
        for (String url : imageUrls) {
            VisitImage img = new VisitImage();
            img.url = url;
            img.displayOrder = order;
            v.images.add(img);
            order++;
        }

        return v;
    }

    // Support
    @TestVisible private static final String DLP_ISSUE = 'DLP Issue';
    private static final String CASE_ORIGIN = 'Web';
    private static final String CASE_STATUS = 'New';
    @TestVisible private static final String CASE_FIELDS_REQUIRED = 'Choose the issue, the property and the unit, and enter a subject and a description.';
    @TestVisible private static final String CASE_SUBJECT_TOO_LONG = 'The subject can have at most 255 characters.';
    @TestVisible private static final String CASE_DLP_REQUIRED = 'Choose the location, the category and the sub category of the defect.';
    @TestVisible private static final String CASE_DLP_NONE = 'This unit has no defects liability period, so a DLP issue cannot be raised for it.';
    @TestVisible private static final String CASE_DLP_NOT_STARTED = 'The defects liability period of this unit starts on {0}.';
    @TestVisible private static final String CASE_DLP_ENDED = 'The defects liability period of this unit ended on {0}, so a DLP issue can no longer be raised for it.';
    @TestVisible private static final String CASE_NOT_A_CUSTOMER = 'Only customers can raise a service request.';
    @TestVisible private static final String CASE_UNIT_UNKNOWN = 'Choose one of your own units.';
    @TestVisible private static final String CASE_NOT_SAVED = 'Your service request could not be raised right now. Please try again.';

    public class SupportIssueOption {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
    @AuraEnabled public Boolean requiresDetails;
}

public class ProjectUnitGroup {
    @AuraEnabled public String project;              // matches a PropertyOption.value from propertyOptions
    @AuraEnabled public List<PropertyOption> units;
}

public class DlpSubCategoryOption {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
}

public class DlpMasterCategoryOption {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
    @AuraEnabled public List<DlpSubCategoryOption> subCategories;
}

public class DlpLocationOption {
    @AuraEnabled public String label;
    @AuraEnabled public String value;
    @AuraEnabled public List<DlpMasterCategoryOption> masterCategories;
}

public class SupportServiceRequest {
    @AuraEnabled public String id;
    @AuraEnabled public String serviceRequestId;
    @AuraEnabled public String subject;
    @AuraEnabled public String description;
    @AuraEnabled public String projectName;
    @AuraEnabled public String propertyName;
    @AuraEnabled public String unitName;
    @AuraEnabled public String type;
    @AuraEnabled public String status;
    @AuraEnabled public String createdDate;
}

// The defects liability period of one booking, shown above the table while it is still running
public class DlpPeriod {
    @AuraEnabled public String opportunityId;
    @AuraEnabled public String unitName;
    @AuraEnabled public String projectName;
    @AuraEnabled public String startDate;
    @AuraEnabled public String endDate;
    @AuraEnabled public String label;
}

public class SupportPageData {
    @AuraEnabled public String description;
    @AuraEnabled public String dlpLabel;
    @AuraEnabled public String dlpStartDate;
    @AuraEnabled public String dlpEndDate;
    // One per booking whose DLP has not ended; the page shows a chip for each
    @AuraEnabled public List<DlpPeriod> dlpPeriods;
    @AuraEnabled public List<SupportServiceRequest> serviceRequests;
    @AuraEnabled public List<PropertyOption> projectFilters;
    @AuraEnabled public List<SupportIssueOption> issueOptions;
    @AuraEnabled public List<PropertyOption> propertyOptions;      // projects, for "Select Property"
    @AuraEnabled public List<ProjectUnitGroup> projectUnitGroups;  // units per project
    @AuraEnabled public List<DlpLocationOption> dlpLocations;      // Location -> Master Category -> Sub Category
    @AuraEnabled public String emptyStateImageUrl;
}

public class SupportActionResponse {
    @AuraEnabled public Boolean success;
    @AuraEnabled public String title;
    @AuraEnabled public String message;
    @AuraEnabled public String serviceRequestId;
}

// The customer's support page: their own cases, and the projects and units they have bought, for a new request.
// cacheable: the page wires this and calls refreshApex after a request is raised
@AuraEnabled(cacheable=true)
public static SupportPageData getSupportPageData() {
    try {
        SupportPageData data = new SupportPageData();
        data.description = 'Manage your support tickets with John Keels Properties . by viewing or raising them '
            + 'below. Stay informed on your inquiries, access details of ongoing support issues, and respond '
            + 'promptly to updates. Our team is dedicated to providing you with effective support. For any '
            + 'questions or additional assistance, please don\u2019t hesitate to contact our support team.';

        Id accountId = getCurrentAccountId();
        data.serviceRequests = casesOf(accountId);
        Map<Id, PropertyOption> projectsById = new Map<Id, PropertyOption>();
        Map<Id, List<PropertyOption>> unitsByProject = new Map<Id, List<PropertyOption>>();
        Set<Id> seenUnits = new Set<Id>();
        for (Opportunity booking : bookingsOf(accountId)) {
            Id projectId = booking.Unit__r.Floor__r.Block__r.Project__c;
            String projectName = booking.Unit__r.Floor__r.Block__r.Project__r == null
                ? null : booking.Unit__r.Floor__r.Block__r.Project__r.Name;
            if (projectId == null) {
                projectId = booking.Project__c;
                projectName = booking.Project__r == null ? '' : booking.Project__r.Name;
            }
            if (projectId == null) {
                continue;
            }
            if (!projectsById.containsKey(projectId)) {
                projectsById.put(projectId, buildOption(projectName, projectId));
                unitsByProject.put(projectId, new List<PropertyOption>());
            }
            if (booking.Unit__c != null && !seenUnits.contains(booking.Unit__c)) {
                seenUnits.add(booking.Unit__c);
                unitsByProject.get(projectId).add(buildOption(booking.Unit__r.Unit_Name_Code__c, booking.Unit__c));
            }
        }
        data.propertyOptions = projectsById.values();
        data.projectUnitGroups = new List<ProjectUnitGroup>();
        for (Id projectId : projectsById.keySet()) {
            ProjectUnitGroup unitsOfProject = new ProjectUnitGroup();
            unitsOfProject.project = projectId;
            unitsOfProject.units = unitsByProject.get(projectId);
            data.projectUnitGroups.add(unitsOfProject);
        }
        // The filter offers the projects the customer's own cases are on
        Map<String, PropertyOption> filters = new Map<String, PropertyOption>();
        for (SupportServiceRequest request : data.serviceRequests) {
            if (String.isNotBlank(request.projectName)) {
                filters.put(request.projectName, buildOption(request.projectName, request.projectName));
            }
        }
        data.projectFilters = new List<PropertyOption>{ buildOption('All Projects', '') };
        data.projectFilters.addAll(filters.values());

        // "Select an issue" is the Case Type picklist
        data.issueOptions = new List<SupportIssueOption>();
        for (Schema.PicklistEntry entry : Case.Type.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                data.issueOptions.add(buildIssueOption(entry.getLabel(), entry.getValue(), DLP_ISSUE.equals(entry.getValue())));
            }
        }
        data.dlpLocations = buildDlpLocations();
        data.dlpPeriods = dlpPeriodsOf(accountId);
        if (!data.dlpPeriods.isEmpty()) {
            data.dlpStartDate = data.dlpPeriods[0].startDate;
            data.dlpEndDate = data.dlpPeriods[0].endDate;
            data.dlpLabel = data.dlpPeriods[0].label;
        }
        data.emptyStateImageUrl = '/resource/SupportEmptyState';
        return data;
    } catch (Exception e) {
        throw buildAuraException('Unable to load support data: ' + e.getMessage());
    }
}

// The defects liability periods of this customer's bookings that are still running (an ended one is not shown)
private static List<DlpPeriod> dlpPeriodsOf(Id accountId) {
    List<DlpPeriod> periods = new List<DlpPeriod>();
    Date today = Date.today();
    for (Opportunity booking : bookingsOf(accountId)) {
        if (booking.DLP_Start_Date__c == null || booking.DLP_End_Date__c == null || booking.DLP_End_Date__c < today) {
            continue;
        }
        DlpPeriod period = new DlpPeriod();
        period.opportunityId = booking.Id;
        period.unitName = booking.Unit__r == null ? '' : booking.Unit__r.Unit_Name_Code__c;
        period.projectName = booking.Unit__r != null && booking.Unit__r.Floor__r != null
            && booking.Unit__r.Floor__r.Block__r != null && booking.Unit__r.Floor__r.Block__r.Project__r != null
                ? booking.Unit__r.Floor__r.Block__r.Project__r.Name
                : (booking.Project__r == null ? '' : booking.Project__r.Name);
        period.startDate = fmtDate(booking.DLP_Start_Date__c);
        period.endDate = fmtDate(booking.DLP_End_Date__c);
        String unitPart = String.isBlank(period.unitName) ? '' : ' - ' + period.unitName;
        period.label = 'Defects Liability Period(DLP)' + unitPart + ': ' + period.startDate + '-' + period.endDate;
        periods.add(period);
    }
    return periods;
}

// The account's bookings that carry a unit: what the customer has bought
private static List<Opportunity> bookingsOf(Id accountId) {
    if (accountId == null) {
        return new List<Opportunity>();
    }
    return [
        SELECT Id, Project__c, Project__r.Name, Unit__c, Unit__r.Unit_Name_Code__c,
            Unit__r.Floor__r.Block__r.Project__c, Unit__r.Floor__r.Block__r.Project__r.Name, CS_Member__c,
            DLP_Start_Date__c, DLP_End_Date__c
        FROM Opportunity
        WHERE AccountId = :accountId AND Unit__c != null
        WITH SYSTEM_MODE
        ORDER BY Unit__r.Unit_Name_Code__c
    ];
}

// Every case this customer has raised, newest first
private static List<SupportServiceRequest> casesOf(Id accountId) {
    List<SupportServiceRequest> requests = new List<SupportServiceRequest>();
    if (accountId == null) {
        return requests;
    }
    for (Case ticket : [
        SELECT Id, CaseNumber, Subject, Description, Type, Status, CreatedDate,
            Project__r.Name, Unit__r.Unit_Name_Code__c
        FROM Case
        WHERE AccountId = :accountId
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC
    ]) {
        SupportServiceRequest request = new SupportServiceRequest();
        request.id = ticket.Id;
        request.serviceRequestId = ticket.CaseNumber;
        request.subject = ticket.Subject;
        request.description = ticket.Description;
        request.projectName = ticket.Project__r == null ? '' : ticket.Project__r.Name;
        request.propertyName = request.projectName;
        request.unitName = ticket.Unit__r == null ? '' : ticket.Unit__r.Unit_Name_Code__c;
        request.type = ticket.Type;
        request.status = ticket.Status;
        request.createdDate = ticket.CreatedDate.format('dd/MM/yyyy');
        requests.add(request);
    }
    return requests;
}


// "Raise a Service Request": a Case on the customer's own unit, owned by the CS Member of that booking.
@AuraEnabled
public static SupportActionResponse createServiceRequest(
    String issueType,
    String propertyName,
    String unitNumber,
    String subject,
    String description,
    String dlpLocation,
    String dlpMasterCategory,
    String dlpSubCategory
) {
    String type = issueType == null ? '' : issueType.trim();
    String heading = subject == null ? '' : subject.trim();
    String detail = description == null ? '' : description.trim();
    if (String.isBlank(type) || String.isBlank(propertyName) || String.isBlank(unitNumber)
            || String.isBlank(heading) || String.isBlank(detail)) {
        throw buildAuraException(CASE_FIELDS_REQUIRED);
    }
    if (heading.length() > 255) {
        throw buildAuraException(CASE_SUBJECT_TOO_LONG);
    }
    if (DLP_ISSUE.equals(type)
            && (String.isBlank(dlpLocation) || String.isBlank(dlpMasterCategory) || String.isBlank(dlpSubCategory))) {
        throw buildAuraException(CASE_DLP_REQUIRED);
    }
    Id accountId = getCurrentAccountId();
    if (accountId == null) {
        throw buildAuraException(CASE_NOT_A_CUSTOMER);
    }
    // The unit must be one this customer has bought; its booking gives the opportunity and the CS Member
    Opportunity booking = null;
    for (Opportunity owned : bookingsOf(accountId)) {
        if (String.valueOf(owned.Unit__c) == unitNumber) {
            booking = owned;
            break;
        }
    }
    if (booking == null) {
        throw buildAuraException(CASE_UNIT_UNKNOWN);
    }
    // A defect can only be reported while that booking's defects liability period is running
    if (DLP_ISSUE.equals(type)) {
        Date today = Date.today();
        if (booking.DLP_Start_Date__c == null || booking.DLP_End_Date__c == null) {
            throw buildAuraException(CASE_DLP_NONE);
        }
        if (today < booking.DLP_Start_Date__c) {
            throw buildAuraException(String.format(CASE_DLP_NOT_STARTED, new List<Object>{ fmtDate(booking.DLP_Start_Date__c) }));
        }
        if (today > booking.DLP_End_Date__c) {
            throw buildAuraException(String.format(CASE_DLP_ENDED, new List<Object>{ fmtDate(booking.DLP_End_Date__c) }));
        }
    }
    Id projectId = booking.Unit__r.Floor__r.Block__r.Project__c != null
        ? booking.Unit__r.Floor__r.Block__r.Project__c : booking.Project__c;
    Case ticket = new Case(
        AccountId = accountId,
        ContactId = currentContactId(),
        Opportunity__c = booking.Id,
        Project__c = projectId,
        Unit__c = booking.Unit__c,
        Type = type,
        Subject = heading,
        Description = detail,
        Origin = CASE_ORIGIN,
        Status = CASE_STATUS
    );
    if (DLP_ISSUE.equals(type)) {
        ticket.Location__c = dlpLocation;
        ticket.Master_Category__c = dlpMasterCategory;
        ticket.Sub_category__c = dlpSubCategory;
    }
    if (booking.CS_Member__c != null) {
        ticket.OwnerId = booking.CS_Member__c;
    }
    try {
        insert as system ticket;
    } catch (DmlException e) {
        System.debug(LoggingLevel.ERROR, 'Customer Portal service request not saved: ' + e.getMessage());
        throw buildAuraException(CASE_NOT_SAVED);
    }
    SupportActionResponse response = new SupportActionResponse();
    response.success = true;
    response.title = 'Your service request has been raised!';
    response.message = 'We have received your service request and it is now being reviewed by our team. '
        + 'You will receive a response shortly. Thank you for contacting John Keells Properties . '
        + 'For any questions or assistance, please don\u2019t hesitate to contact our support team.';
    response.serviceRequestId = [SELECT CaseNumber FROM Case WHERE Id = :ticket.Id WITH SYSTEM_MODE].CaseNumber;
    return response;
}

private static Id currentContactId() {
    for (User me : [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1]) {
        return me.ContactId;
    }
    return null;
}

private static SupportIssueOption buildIssueOption(String label, String value, Boolean requiresDetails) {
    SupportIssueOption opt = new SupportIssueOption();
    opt.label = label;
    opt.value = value;
    opt.requiresDetails = requiresDetails;
    return opt;
}

private static ProjectUnitGroup buildProjectUnitGroup(String project, List<String> unitNumbers) {
    ProjectUnitGroup g = new ProjectUnitGroup();
    g.project = project;
    g.units = new List<PropertyOption>();
    for (String u : unitNumbers) {
        g.units.add(buildOption(u, u));
    }
    return g;
}

private static List<DlpLocationOption> buildDlpLocations() {
    List<DlpLocationOption> locations = new List<DlpLocationOption>();

    locations.add(buildDlpLocation('Colombo', new List<Object[]>{
        new Object[]{ 'Structural', new List<String>{ 'Cracks', 'Settlement', 'Dampness' } },
        new Object[]{ 'Electrical', new List<String>{ 'Wiring Fault', 'Switch/Socket Issue', 'DB Issue' } },
        new Object[]{ 'Plumbing', new List<String>{ 'Leakage', 'Blockage', 'Low Pressure' } }
    }));

    locations.add(buildDlpLocation('Kandy', new List<Object[]>{
        new Object[]{ 'Structural', new List<String>{ 'Cracks', 'Roof Leak' } },
        new Object[]{ 'Finishes', new List<String>{ 'Paint Peeling', 'Tile Damage', 'Door/Window Fit' } }
    }));

    locations.add(buildDlpLocation('Galle', new List<Object[]>{
        new Object[]{ 'Electrical', new List<String>{ 'Wiring Fault', 'Lighting Issue' } },
        new Object[]{ 'Plumbing', new List<String>{ 'Leakage', 'Blockage' } }
    }));

    return locations;
}

private static DlpLocationOption buildDlpLocation(String name, List<Object[]> masterCategoryDefs) {
    DlpLocationOption loc = new DlpLocationOption();
    loc.label = name;
    loc.value = name;
    loc.masterCategories = new List<DlpMasterCategoryOption>();

    for (Object[] def : masterCategoryDefs) {
        String masterLabel = (String) def[0];
        List<String> subLabels = (List<String>) def[1];

        DlpMasterCategoryOption master = new DlpMasterCategoryOption();
        master.label = masterLabel;
        master.value = masterLabel;
        master.subCategories = new List<DlpSubCategoryOption>();
        for (String subLabel : subLabels) {
            DlpSubCategoryOption sub = new DlpSubCategoryOption();
            sub.label = subLabel;
            sub.value = subLabel;
            master.subCategories.add(sub);
        }
        loc.masterCategories.add(master);
    }

    return loc;
}
     public class EventWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String eventDate;
        @AuraEnabled public String startTime;
        @AuraEnabled public String endTime;
        @AuraEnabled public String location;
        @AuraEnabled public Boolean isRegistered;
    }

    public class EventRegistrationResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Boolean isRegistered;
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public String eventId;
    }

    // The events, from the Event records; the ones already over are left out. An event the customer's account has an
    // Event Registration for comes back as registered.
    // cacheable: the page wires this and calls refreshApex after a registration (the cache is per user)
    @AuraEnabled(cacheable=true)
    public static List<EventWrapper> getEvents() {
        try {
            Id accountId = getCurrentAccountId();
            Set<Id> registered = new Set<Id>();
            if (accountId != null) {
                for (Event_Registration__c booking : [
                    SELECT Event__c FROM Event_Registration__c WHERE Account__c = :accountId WITH SYSTEM_MODE
                ]) {
                    registered.add(booking.Event__c);
                }
            }
            // Coming up first (soonest first), then the ones already over (most recent first)
            List<EventWrapper> upcoming = new List<EventWrapper>();
            List<EventWrapper> past = new List<EventWrapper>();
            Datetime now = System.now();
            for (Event__c record : [
                SELECT Id, Name, Description__c, Start_Date_Time__c, End_Date_Time__c,
                    Venue__Street__s, Venue__City__s, Venue__StateCode__s, Venue__PostalCode__s, Venue__CountryCode__s
                FROM Event__c
                WITH SYSTEM_MODE
                ORDER BY Start_Date_Time__c
            ]) {
                EventWrapper item = new EventWrapper();
                item.id = record.Id;
                item.title = record.Name;
                item.description = record.Description__c;
                // One day shows one date; an event that runs over several days shows both
                Datetime startsAt = record.Start_Date_Time__c;
                Datetime endsAt = record.End_Date_Time__c;
                if (startsAt == null) {
                    item.eventDate = '';
                } else if (endsAt != null && endsAt.date() != startsAt.date()) {
                    item.eventDate = startsAt.format('MMM dd') + ' - ' + endsAt.format('MMM dd, yyyy');
                } else {
                    item.eventDate = startsAt.format('MMM dd, yyyy');
                }
                item.startTime = record.Start_Date_Time__c == null ? '' : record.Start_Date_Time__c.format('h:mm a');
                item.endTime = record.End_Date_Time__c == null ? '' : record.End_Date_Time__c.format('h:mm a');
                item.location = joinNonBlank(new List<String>{
                    record.Venue__Street__s, record.Venue__City__s, record.Venue__StateCode__s,
                    record.Venue__PostalCode__s, record.Venue__CountryCode__s
                });
                item.isRegistered = registered.contains(record.Id);
                Datetime ends = record.End_Date_Time__c == null ? record.Start_Date_Time__c : record.End_Date_Time__c;
                if (ends == null || ends >= now) {
                    upcoming.add(item);
                } else {
                    past.add(item);
                }
            }
            // the ones already over come after, most recent first (Apex cannot insert at 0 in an empty list)
            for (Integer i = past.size() - 1; i >= 0; i--) {
                upcoming.add(past[i]);
            }
            return upcoming;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Customer Portal events: ' + e.getTypeName() + ' at line '
                + e.getLineNumber() + ': ' + e.getMessage());
            throw buildAuraException('Unable to load events: ' + e.getMessage());
        }
    }

    // "Register Now": an Event Registration for the customer's account, once per event
    @AuraEnabled
    public static EventRegistrationResponse registerForEvent(String eventId, String eventTitle, String eventDate,
            String startTime, String endTime, String eventLocation) {
        if (String.isBlank(eventId)) {
            throw buildAuraException('Event id and title are required.');
        }
        try {
            Id accountId = getCurrentAccountId();
            if (accountId == null) {
                throw buildAuraException('Only customers can register for an event.');
            }
            Id recordId = Id.valueOf(eventId);
            List<Event__c> events = [SELECT Id, Name FROM Event__c WHERE Id = :recordId WITH SYSTEM_MODE LIMIT 1];
            if (events.isEmpty()) {
                throw buildAuraException('This event is no longer available.');
            }
            EventRegistrationResponse response = new EventRegistrationResponse();
            response.eventId = eventId;
            response.isRegistered = true;
            response.success = true;
            response.title = 'Registration Successful';
            Integer already = [
                SELECT COUNT() FROM Event_Registration__c
                WHERE Account__c = :accountId AND Event__c = :recordId WITH SYSTEM_MODE
            ];
            if (already > 0) {
                response.message = 'You are already registered for this event.';
                return response;
            }
            insert as system new Event_Registration__c(Account__c = accountId, Event__c = recordId);
            response.message = 'You have been registered for this event.';
            return response;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException('Unable to register for the event: ' + e.getMessage());
        }
    }

    public class FAQItem {
        @AuraEnabled public String id;
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public Integer displayOrder;
    }

    public class FAQCategory {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public List<FAQItem> faqs;
    }

    public class FAQPageData {
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public List<FAQCategory> categories;
    }

    @AuraEnabled(cacheable=true)
    public static FAQPageData getFAQs() {
        try {
            FAQPageData data = new FAQPageData();

            data.title = 'FAQ\u2019s';
            data.description = 'Explore answers to common questions about John Keels Properties below. '
                + 'Find information on bookings, payments, property features, and more. Our FAQ section '
                + 'aims to provide clarity and assistance. For any questions not covered here, please '
                + 'contact our support team. We\u2019re here to help!';

            data.categories = buildFaqCategories();

            return data;
        } catch (Exception e) {
            throw buildAuraException('Unable to load FAQs: ' + e.getMessage());
        }
    }

    // The FAQ records, grouped under one tab per Type, in the order the Type picklist defines
    private static List<FAQCategory> buildFaqCategories() {
        Map<String, FAQCategory> byType = new Map<String, FAQCategory>();
        List<FAQCategory> categories = new List<FAQCategory>();
        // the picklist order decides the tab order, so a new Type appears without a code change
        for (Schema.PicklistEntry entry : FAQ__c.Type__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            FAQCategory category = new FAQCategory();
            category.key = entry.getValue().toLowerCase().replaceAll('[^a-z0-9]+', '-');
            category.label = entry.getLabel();
            category.faqs = new List<FAQItem>();
            byType.put(entry.getValue(), category);
            categories.add(category);
        }
        Integer order = 0;
        for (FAQ__c faq : [
            SELECT Id, Type__c, Question__c, Answer__c
            FROM FAQ__c
            WHERE Type__c != null
            WITH SYSTEM_MODE
            ORDER BY Type__c, Name
        ]) {
            if (String.isBlank(faq.Question__c)) {
                continue;   // a long text field cannot be filtered in SOQL
            }
            FAQCategory category = byType.get(faq.Type__c);
            if (category == null) {
                // a Type that is no longer in the picklist still gets its own tab
                category = new FAQCategory();
                category.key = faq.Type__c.toLowerCase().replaceAll('[^a-z0-9]+', '-');
                category.label = faq.Type__c;
                category.faqs = new List<FAQItem>();
                byType.put(faq.Type__c, category);
                categories.add(category);
            }
            FAQItem item = new FAQItem();
            item.id = faq.Id;
            item.question = faq.Question__c;
            item.answer = faq.Answer__c;
            item.displayOrder = ++order;
            category.faqs.add(item);
        }
        // tabs with no questions are not shown
        List<FAQCategory> withQuestions = new List<FAQCategory>();
        for (FAQCategory category : categories) {
            if (!category.faqs.isEmpty()) {
                withQuestions.add(category);
            }
        }
        return withQuestions;
    }


    public class DocImage {
        @AuraEnabled public String url;
        @AuraEnabled public Integer displayOrder;
    }

    public class DocumentWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String documentUrl;
    }

    public class DocumentCategory {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public List<DocumentWrapper> documents;
    }

    public class DocumentProject {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String address;
        @AuraEnabled public List<DocImage> images;
        @AuraEnabled public List<DocumentCategory> documentCategories;
    }

    public class MyDocumentsPageData {
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public List<DocumentProject> projects;
    }

    @AuraEnabled(cacheable=true)
    public static MyDocumentsPageData getMyDocumentsPageData() {
        try {
            MyDocumentsPageData data = new MyDocumentsPageData();

            data.title = 'My Documents';
            data.description = 'Manage your documents with John Keels Properties by viewing, downloading, '
                + 'and organizing them in one place. Access important files, agreements, reports, and '
                + 'supporting documents whenever needed. Stay up to date with your records and ensure all '
                + 'required documentation is readily available. For any questions or assistance regarding '
                + 'your documents, please contact our support team.';

            data.projects = buildDocumentProjects();

            return data;
        } catch (Exception e) {
            throw buildAuraException('Unable to load documents: ' + e.getMessage());
        }
    }

    private static List<DocumentProject> buildDocumentProjects() {
        List<DocumentProject> projects = new List<DocumentProject>();

        projects.add(buildDocumentProject(
            'DOC-PRJ-001',
            'JK Kingsland',
            'Plot No-15, VIP Colony, Nayapally, Bhubaneswar',
            new List<String>{
                'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800',
                'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=800',
                'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=800'
            }
        ));

        projects.add(buildDocumentProject(
            'DOC-PRJ-002',
            'JK Pallaciya',
            'Plot No-15, VIP Colony, Nayapally, Bhubaneswar',
            new List<String>{
                'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=800',
                'https://images.unsplash.com/photo-1571055107559-3e67626fa8be?w=800'
            }
        ));

        return projects;
    }

    private static DocumentProject buildDocumentProject(String id, String name, String address, List<String> imageUrls) {
        DocumentProject p = new DocumentProject();
        p.id = id;
        p.name = name;
        p.address = address;

        p.images = new List<DocImage>();
        Integer order = 1;
        for (String url : imageUrls) {
            DocImage img = new DocImage();
            img.url = url;
            img.displayOrder = order;
            p.images.add(img);
            order++;
        }

        p.documentCategories = new List<DocumentCategory>{
            buildDocumentCategory('myDocuments', 'My Documents', new List<DocumentWrapper>{
                buildDocumentWrapper(id + '-DOC-TIN', 'TIN', 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800' + id + '.pdf')
            }),
            buildDocumentCategory('propertyDocuments', 'Property Documents', new List<DocumentWrapper>{
                buildDocumentWrapper(id + '-DOC-SALEDEED', 'Sale Deed', 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800' + id + '.pdf'),
                buildDocumentWrapper(id + '-DOC-AGREEMENT', 'Agreement of Sale', 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800' + id + '.pdf')
            }),
            buildDocumentCategory('homeLoanDocuments', 'Home Loan Documents', new List<DocumentWrapper>{
                buildDocumentWrapper(id + '-DOC-TPA', 'TPA', 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800' + id + '.pdf'),
                buildDocumentWrapper(id + '-DOC-NOC', 'Builder NOC', 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800' + id + '.pdf')
            })
        };

        return p;
    }

    private static DocumentCategory buildDocumentCategory(String key, String label, List<DocumentWrapper> documents) {
        DocumentCategory cat = new DocumentCategory();
        cat.key = key;
        cat.label = label;
        cat.documents = documents;
        return cat;
    }

    private static DocumentWrapper buildDocumentWrapper(String id, String name, String documentUrl) {
        DocumentWrapper doc = new DocumentWrapper();
        doc.id = id;
        doc.name = name;
        doc.documentUrl = documentUrl;
        return doc;
    }

    public class SimplePageData {
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        // Rich text (HTML) kept on the Portal Info record of Type "Customer", as the partner portal does with its own
        @AuraEnabled public String body;
    }

    // Portal_Info__c.Type__c of the customer portal's record (one record per Type, see PortalInfoTrigger)
    private static final String CUSTOMER_INFO = 'Customer';

    // The About Us and Terms & Conditions text of the customer portal; blank until the record is filled in
    private static Portal_Info__c customerInfo() {
        for (Portal_Info__c record : [
            SELECT About_Us__c, Terms_Condition__c
            FROM Portal_Info__c
            WHERE Type__c = :CUSTOMER_INFO
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ]) {
            return record;
        }
        return new Portal_Info__c();
    }

    @AuraEnabled(cacheable=true)
    public static SimplePageData getAboutUsData() {
        try {
            SimplePageData data = new SimplePageData();
            data.title = 'About Us';
            data.description = 'Update your personal information, manage preferences on your John Keels '
                + 'Properties . profile dashboard.';
            data.body = customerInfo().About_Us__c;
            return data;
        } catch (Exception e) {
            throw buildAuraException('Unable to load About Us content: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static SimplePageData getTermsConditionsData() {
        try {
            SimplePageData data = new SimplePageData();
            data.title = 'Terms & Conditions';
            data.description = 'Explore the terms and conditions of John Keels Properties . for comprehensive '
                + 'guidelines and policies. Understand your rights and responsibilities, and stay informed '
                + 'about our procedures and regulations. Our terms and conditions aim to provide clarity and '
                + 'ensure a smooth experience. For more details or specific inquiries, please feel free to '
                + 'reach out to our team.';
            data.body = customerInfo().Terms_Condition__c;
            return data;
        } catch (Exception e) {
            throw buildAuraException('Unable to load Terms & Conditions content: ' + e.getMessage());
        }
    }

     public class DashHeroSlide {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Integer displayOrder;
    }
 
    public class DashQuickLink {
        @AuraEnabled public String label;
        @AuraEnabled public String page;    
        @AuraEnabled public String iconKey;   
    }
 
    public class DashSupportData {
        @AuraEnabled public Integer pendingCount;
        @AuraEnabled public String status;
        @AuraEnabled public Integer progress; 
    }
 
    public class DashHandoverSummary {
        @AuraEnabled public Integer percentage;
        @AuraEnabled public String status;
    }
 
    public class DashboardData {
        @AuraEnabled public String customerName;
        @AuraEnabled public String customerId;
        @AuraEnabled public String dashboardDate;
        @AuraEnabled public List<DashHeroSlide> heroSlides;
        @AuraEnabled public List<DashQuickLink> quickLinks;
        @AuraEnabled public DashSupportData supportData;
        @AuraEnabled public DashHandoverSummary handoverData;
    }
 
     public class HandoverChecklistItem {
        @AuraEnabled public String id;
        @AuraEnabled public Integer srNo;
        @AuraEnabled public String activity;
        @AuraEnabled public String description;
        @AuraEnabled public String status;   // 'Completed' | 'Pending'
        @AuraEnabled public String remarks;
    }

    public class HandoverChecklistCard {
        @AuraEnabled public String id;
        @AuraEnabled public String title;          // 'Type A'
        @AuraEnabled public String description;    // 'No action items required'
        @AuraEnabled public Integer actionItemCount;
        @AuraEnabled public String status;         // 'Completed' | 'In Progress'
        @AuraEnabled public String statusClass;    // 'completed' | 'inprogress'
        @AuraEnabled public String imageUrl;       // reserved for a real illustration later
        @AuraEnabled public Integer displayOrder;
        @AuraEnabled public List<HandoverChecklistItem> checklistItems;
    }

    public class HandoverProperty {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String projectName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String unitTypes;      // e.g. '2 | 3 | 4 RESIDENCES'
    }

    public class HandoverPageData {
        @AuraEnabled public String title;
        @AuraEnabled public List<HandoverProperty> properties;
        @AuraEnabled public HandoverProperty selectedProperty;
        @AuraEnabled public List<HandoverChecklistCard> checklistCards;
    }
 
    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboardData() {
        try {
            DashboardData d = new DashboardData();
            d.customerName = 'Ankush';
            d.customerId   = '0001';
            d.dashboardDate = Datetime.now().format('dd MMM, yyyy');
 
            d.heroSlides = new List<DashHeroSlide>{
                buildHeroSlide('HERO-1', 'The Monarch', 'Apartments',
                    'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00?w=1600', 1),
                buildHeroSlide('HERO-2', 'JK Kingsland', 'Apartments',
                    'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=1600', 2)
            };
 
            d.quickLinks = new List<DashQuickLink>{
                buildQuickLink('My Properties', 'myProperties', 'properties'),
                buildQuickLink('Construction Status', 'constructionStatus', 'construction'),
                buildQuickLink('My Documents', 'myDocuments', 'documents'),
                buildQuickLink('My Accounts', 'myAccounts', 'accounts')
            };
 
            DashSupportData s = new DashSupportData();
            s.pendingCount = 3;
            s.status = 'Pending';
            s.progress = 75;
            d.supportData = s;
 
            DashHandoverSummary h = new DashHandoverSummary();
            h.percentage = 27;
            h.status = 'Complete';
            d.handoverData = h;
 
            return d;
        } catch (Exception e) {
            throw buildAuraException('Unable to load dashboard data: ' + e.getMessage());
        }
    }
 
    private static DashHeroSlide buildHeroSlide(String id, String title, String subtitle, String url, Integer ord) {
        DashHeroSlide s = new DashHeroSlide();
        s.id = id; s.title = title; s.subtitle = subtitle; s.imageUrl = url; s.displayOrder = ord;
        return s;
    }
 
    private static DashQuickLink buildQuickLink(String label, String page, String iconKey) {
        DashQuickLink q = new DashQuickLink();
        q.label = label; q.page = page; q.iconKey = iconKey;
        return q;
    }
 
    @AuraEnabled
    public static HandoverPageData getHandoverData(String propertyId) {
        try {
            List<HandoverProperty> props = new List<HandoverProperty>{
                buildHandoverProperty('HP-001', 'Sunrise Ridge Villas', 'Sunrise Ridge Villas Residences',
                    'https://images.unsplash.com/photo-1449844908441-8829872d2607?w=200', '2 | 3 BHK'),
                buildHandoverProperty('HP-002', 'JK Kingsland', 'JK Kingsland Residences',
                    'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=200', '2 | 3 | 4 RESIDENCES'),
                buildHandoverProperty('HP-003', 'Tri-Zen Apartments', 'Tri-Zen Apartments Residences',
                    'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00?w=200', '2 | 3 | 4 RESIDENCES')
            };

            HandoverProperty selected = props[0];
            for (HandoverProperty p : props) {
                if (p.id == propertyId) { selected = p; break; }
            }

            HandoverPageData data = new HandoverPageData();
            data.title = 'Handover (Checklist for Final Handing over)';
            data.properties = props;
            data.selectedProperty = selected;
            data.checklistCards = buildHandoverChecklistCards(selected.id);
            return data;
        } catch (Exception e) {
            throw buildAuraException('Unable to load handover data: ' + e.getMessage());
        }
    }

    private static HandoverProperty buildHandoverProperty(String id, String name, String projectName, String imageUrl, String unitTypes) {
        HandoverProperty p = new HandoverProperty();
        p.id = id; p.name = name; p.projectName = projectName; p.imageUrl = imageUrl; p.unitTypes = unitTypes;
        return p;
    }

    private static List<HandoverChecklistCard> buildHandoverChecklistCards(String propertyId) {
        List<HandoverChecklistCard> cards = new List<HandoverChecklistCard>();
        cards.add(buildCard(propertyId, 'A', 'Type A', 0, buildTypeAItems(propertyId), 1));
        cards.add(buildCard(propertyId, 'B', 'Type B', 13, buildItems(propertyId, 'B', 13), 2));
        cards.add(buildCard(propertyId, 'C', 'Type C', 26, buildItems(propertyId, 'C', 26), 3));
        return cards;
    }

    private static HandoverChecklistCard buildCard(String propertyId, String typeCode, String title, Integer actionCount, List<HandoverChecklistItem> items, Integer displayOrder) {
        HandoverChecklistCard c = new HandoverChecklistCard();
        c.id = propertyId + '-TYPE-' + typeCode;
        c.title = title;
        c.description = actionCount == 0 ? 'No action items required' : actionCount + ' action items required';
        c.actionItemCount = actionCount;
        c.status = actionCount == 0 ? 'Completed' : 'In Progress';
        c.statusClass = actionCount == 0 ? 'completed' : 'inprogress';
        c.imageUrl = null; // no static resource yet — LWC renders a built-in checklist icon
        c.displayOrder = displayOrder;
        c.checklistItems = items;
        return c;
    }

    private static List<HandoverChecklistItem> buildTypeAItems(String propertyId) {
        List<List<String>> rows = new List<List<String>>{
            new List<String>{ 'Flooring', 'Master Bedroom', 'Completed', 'Its Completed' },
            new List<String>{ 'Flooring', 'Other Bedrooms', 'Completed', '' },
            new List<String>{ 'Flooring', 'Living & Dining', 'Completed', '' },
            new List<String>{ 'Kitchen', 'Tiling & Dadoing', 'Completed', '' },
            new List<String>{ 'Kitchen', 'Granite platform', 'Completed', '' },
            new List<String>{ 'Kitchen', 'Stainless steel sink/tap', 'Completed', '' },
            new List<String>{ 'Toilet, Utility & Balcony', 'Flooring & Dadoing', 'Completed', '' }
        };
        List<HandoverChecklistItem> items = new List<HandoverChecklistItem>();
        Integer sr = 1;
        for (List<String> row : rows) {
            HandoverChecklistItem i = new HandoverChecklistItem();
            i.id = propertyId + '-A-CHK-' + sr;
            i.srNo = sr;
            i.activity = row[0];
            i.description = row[1];
            i.status = row[2];
            i.remarks = row[3];
            items.add(i);
            sr++;
        }
        return items;
    }

    private static List<HandoverChecklistItem> buildItems(String propertyId, String typeCode, Integer count) {
        List<String> activities = new List<String>{ 'Electrical', 'Plumbing', 'Painting', 'Carpentry', 'Flooring', 'Kitchen', 'Bathroom Fittings', 'Windows & Doors' };
        List<String> descriptions = new List<String>{ 'Master Bedroom', 'Other Bedrooms', 'Living & Dining', 'Kitchen', 'Balcony', 'Utility Area', 'Common Area', 'Entrance' };
        List<HandoverChecklistItem> items = new List<HandoverChecklistItem>();
        for (Integer i = 1; i <= count; i++) {
            HandoverChecklistItem it = new HandoverChecklistItem();
            it.id = propertyId + '-' + typeCode + '-CHK-' + i;
            it.srNo = i;
            it.activity = activities[Math.mod(i - 1, activities.size())];
            it.description = descriptions[Math.mod(i - 1, descriptions.size())];
            it.status = Math.mod(i, 3) == 0 ? 'Completed' : 'Pending';
            it.remarks = '';
            items.add(it);
        }
        return items;
    }

    // One CRM contact card: the CS Member of one opportunity. A project the customer has booked twice shows two.
    public class LetsTalkContact {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String display;
        @AuraEnabled public String phoneUrl;
        // The unit this contact person looks after, shown above the name
        @AuraEnabled public String unit;
    }

    public class LetsTalkProject {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String propertyAddress;
        @AuraEnabled public String propertyMapUrl;
        @AuraEnabled public String email;
        @AuraEnabled public String emailUrl;
        @AuraEnabled public List<LetsTalkContact> crmContacts;
        @AuraEnabled public String corporateAddress;
        @AuraEnabled public String corporateMapUrl;
    }
    
    public class LetsTalkPageData {
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String defaultProject;
        @AuraEnabled public List<LetsTalkProject> projects;
    }
    
    // The contact details of the projects this customer has an opportunity on: the dropdown lists those projects, and
    // each one shows its own address and email, the CS Member of every opportunity on it, and the company's address.
    @AuraEnabled
    public static LetsTalkPageData getLetsTalkPageData() {
        try {
            LetsTalkPageData data = new LetsTalkPageData();
            data.title = 'Let\u2019s Talk';
            data.description = 'Get in touch with John Keells Properties for any questions, assistance, or '
                + 'support you may need. Find the right contact details for your property, reach our team by '
                + 'email or phone, or locate our offices on the map. We\u2019re here to help and ensure you have '
                + 'a smooth and hassle-free experience. For any specific inquiries, please feel free to reach '
                + 'out to our team.';
            data.projects = letsTalkProjectsOf(getCurrentAccountId());
            data.defaultProject = data.projects.isEmpty() ? null : data.projects[0].id;
            return data;
        } catch (Exception e) {
            throw buildAuraException('Unable to load Lets Talk data: ' + e.getMessage());
        }
    }

    // One entry per project of the account's opportunities, in name order, each with a contact per opportunity
    private static List<LetsTalkProject> letsTalkProjectsOf(Id accountId) {
        List<LetsTalkProject> projects = new List<LetsTalkProject>();
        if (accountId == null) {
            return projects;
        }
        Map<Id, LetsTalkProject> byProject = new Map<Id, LetsTalkProject>();
        for (Opportunity booking : [
            SELECT Id, Project__c, Project__r.Name, Project__r.Email__c,
                Project__r.Project_Location__Street__s, Project__r.Project_Location__City__s,
                Project__r.Project_Location__PostalCode__s, Project__r.Project_Location__StateCode__s,
                Project__r.Project_Location__CountryCode__s,
                Project__r.Project_Location__Latitude__s, Project__r.Project_Location__Longitude__s,
                Project__r.Company__r.Name, Project__r.Company__r.Address__Street__s,
                Project__r.Company__r.Address__City__s, Project__r.Company__r.Address__PostalCode__s,
                Project__r.Company__r.Address__StateCode__s, Project__r.Company__r.Address__CountryCode__s,
                Project__r.Company__r.Address__Latitude__s, Project__r.Company__r.Address__Longitude__s,
                Unit__c, Unit__r.Unit_Name_Code__c,
                CS_Member__c, CS_Member__r.Name, CS_Member__r.FirstName, CS_Member__r.LastName,
                CS_Member__r.Phone, CS_Member__r.MobilePhone
            FROM Opportunity
            WHERE AccountId = :accountId AND Project__c != null
            WITH SYSTEM_MODE
            ORDER BY Project__r.Name, CreatedDate
        ]) {
            Project__c project = booking.Project__r;
            LetsTalkProject entry = byProject.get(booking.Project__c);
            if (entry == null) {
                entry = new LetsTalkProject();
                entry.id = booking.Project__c;
                entry.name = project.Name;
                entry.propertyAddress = joinNonBlank(new List<String>{
                    project.Project_Location__Street__s, project.Project_Location__City__s,
                    project.Project_Location__StateCode__s, project.Project_Location__PostalCode__s,
                    project.Project_Location__CountryCode__s
                });
                entry.propertyMapUrl = mapUrl(project.Project_Location__Latitude__s,
                    project.Project_Location__Longitude__s, entry.propertyAddress);
                entry.email = project.Email__c;
                entry.emailUrl = String.isBlank(project.Email__c) ? null : 'mailto:' + project.Email__c;
                entry.crmContacts = new List<LetsTalkContact>();
                if (project.Company__c != null) {
                    Company__c company = project.Company__r;
                    entry.corporateAddress = joinNonBlank(new List<String>{
                        company.Name, company.Address__Street__s, company.Address__City__s,
                        company.Address__StateCode__s, company.Address__PostalCode__s, company.Address__CountryCode__s
                    });
                    entry.corporateMapUrl = mapUrl(company.Address__Latitude__s, company.Address__Longitude__s,
                        entry.corporateAddress);
                }
                byProject.put(entry.id, entry);
                projects.add(entry);
            }
            // The CS Member of this opportunity; a project booked twice shows both
            if (booking.CS_Member__c != null) {
                String phone = String.isNotBlank(booking.CS_Member__r.MobilePhone)
                    ? booking.CS_Member__r.MobilePhone : booking.CS_Member__r.Phone;
                LetsTalkContact contact = new LetsTalkContact();
                contact.id = booking.Id;
                contact.unit = booking.Unit__c == null ? null : booking.Unit__r.Unit_Name_Code__c;
                // Experience Cloud hides an internal user's Name from portal users (it answers "User<18 digits>"),
                // so the name is built from the first and last name, with Name only as a fallback
                String fullName = (trimmedOrBlank(booking.CS_Member__r.FirstName) + ' '
                    + trimmedOrBlank(booking.CS_Member__r.LastName)).trim();
                contact.name = String.isNotBlank(fullName) ? fullName : booking.CS_Member__r.Name;
                contact.phone = phone;
                contact.display = String.isBlank(phone) ? contact.name : contact.name + ' : ' + phone;
                contact.phoneUrl = String.isBlank(phone) ? null : 'tel:' + phone.replaceAll('[^0-9+]', '');
                entry.crmContacts.add(contact);
            }
        }
        return projects;
    }

    private static String trimmedOrBlank(String value) {
        return value == null ? '' : value.trim();
    }

    // Google Maps at the exact point when the project or company has one, otherwise at the address text
    private static String mapUrl(Decimal latitude, Decimal longitude, String address) {
        if (latitude != null && longitude != null) {
            return 'https://maps.google.com/?q=' + latitude + ',' + longitude;
        }
        return String.isBlank(address) ? null : 'https://maps.google.com/?q=' + EncodingUtil.urlEncode(address, 'UTF-8');
    }

    // ======================================================================================================
    // PROFILE PAGE  (was CustomerPortalProfileController, merged 2026-10-19 so the portal has one controller)
    // ======================================================================================================


    // What the page shows; the methods that change something answer with it again
    public class Profile {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public String phoneCountryCode;
        @AuraEnabled public String phoneNumber;
        @AuraEnabled public String department;
        @AuraEnabled public String username;
        // The account's picture as a data: URL ('data:image/jpeg;base64,...'), or null for the page's default avatar
        @AuraEnabled public String photoUrl;
        @AuraEnabled public Boolean hasPhoto;
        // True when Salesforce keeps the login's old email until the customer confirms the new one (it emails them a link)
        @AuraEnabled public Boolean emailPending;
    }

    @TestVisible private static final String NOT_SIGNED_IN = 'Your session has ended. Please log in again.';
    @TestVisible private static final String NOT_A_CUSTOMER = 'This portal is only for John Keells Properties customers.';
    @TestVisible private static final String FIRST_NAME_REQUIRED = 'Enter your first name.';
    @TestVisible private static final String FIRST_NAME_TOO_LONG = 'Your first name can have at most 40 characters.';
    @TestVisible private static final String LAST_NAME_REQUIRED = 'Enter your last name.';
    @TestVisible private static final String LAST_NAME_TOO_LONG = 'Your last name can have at most 80 characters.';
    @TestVisible private static final String EMAIL_REQUIRED = 'Enter your email address.';
    @TestVisible private static final String EMAIL_TOO_LONG = 'Your email address can have at most 80 characters.';
    @TestVisible private static final String EMAIL_INVALID = 'Enter a valid email address.';
    @TestVisible private static final String COUNTRY_CODE_INVALID = 'Choose the country code of your phone number.';
    @TestVisible private static final String PHONE_REQUIRED = 'Enter your phone number.';
    @TestVisible private static final String PHONE_INVALID = 'Enter a valid phone number of 6 to 15 digits.';
    @TestVisible private static final String DEPARTMENT_TOO_LONG = 'Your department can have at most 80 characters.';
    @TestVisible private static final String PROFILE_NOT_SAVED = 'Your profile could not be saved right now. Please try again.';
    @TestVisible private static final String PICTURE_REQUIRED = 'Choose a photo to upload.';
    @TestVisible private static final String PICTURE_WRONG_TYPE = 'Your photo must be a JPEG or PNG image.';
    @TestVisible private static final String PICTURE_TOO_BIG = 'Your photo must be 2 MB or smaller.';
    @TestVisible private static final String PICTURE_NOT_SAVED = 'Your photo could not be saved right now. Please try again.';
    @TestVisible private static final String PASSWORD_REQUIRED = 'Enter your current password, your new password and the confirmation.';
    @TestVisible private static final String PASSWORD_MISMATCH = 'The new password and the confirmation do not match.';
    @TestVisible private static final String PASSWORD_TOO_WEAK = 'Your new password must have at least 8 characters, with at least one letter and one number.';
    @TestVisible private static final String PASSWORD_SAME = 'Your new password must be different from your current password.';
    @TestVisible private static final String PASSWORD_NOT_CHANGED = 'Your password could not be changed. Check your current password, and choose a new password you have not used recently.';

    private static final Integer MAX_FIRST_NAME = 40;
    private static final Integer MAX_LAST_NAME = 80;
    private static final Integer MAX_EMAIL = 80;
    private static final Integer MAX_DEPARTMENT = 80;
    // The customer profile's password policy: at least 8 characters, letters and numbers mixed, none of the last 3
    private static final Integer MIN_PASSWORD = 8;
    // The country codes the page offers (the org's country list has Sri Lanka, India and the US); Sri Lanka is the default
    private static final String DEFAULT_COUNTRY_CODE = '94';
    private static final List<String> COUNTRY_CODES = new List<String>{ '94', '91', '1' };
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$');
    private static final Pattern PHONE_DIGITS = Pattern.compile('^[0-9]{6,15}$');
    private static final Pattern PHONE_WITH_CODE = Pattern.compile('^\\+([0-9]{1,3})[ -]+(.*)$');
    private static final Pattern LETTER = Pattern.compile('[A-Za-z]');
    private static final Pattern DIGIT = Pattern.compile('[0-9]');

    @TestVisible private static final String PICTURE_TITLE = 'Profile Picture';
    private static final Set<String> PICTURE_TYPES = new Set<String>{ 'image/jpeg', 'image/jpg', 'image/png' };
    // Room for the start of a data: URL ('data:image/jpeg;base64,'), which the page may send in front of the picture
    private static final Integer MAX_DATA_URL_PREFIX = 64;
    // The page sends the picture resized to 512 px; this is the most this method takes
    @TestVisible private static Integer maxPictureBytes = 2 * 1024 * 1024;
    // Pictures up to this size travel inline to the page; a larger one (possible only when someone replaced the file in
    // Salesforce) shows the default avatar
    @TestVisible private static Integer maxInlineBytes = 1536 * 1024;
    private static final Map<String, String> MIME_TYPES = new Map<String, String>{
        'JPG' => 'image/jpeg', 'JPEG' => 'image/jpeg', 'PNG' => 'image/png', 'GIF' => 'image/gif'
    };
    // The account's link to its picture: everybody who can see the account can view the file and nobody can change it
    // through the account (Viewer), for customers as well as internal users (AllUsers). The customer who uploads it owns
    // the file, so they can always replace it.
    private static final String SHARE_VIEWER = 'V';
    private static final String VISIBLE_TO_ALL = 'AllUsers';

    // Site.changePassword; tests replace it, because a test has no site session
    public virtual class SitePasswordChange {
        public virtual PageReference changePassword(String newPassword, String verifyNewPassword, String oldPassword) {
            return Site.changePassword(newPassword, verifyNewPassword, oldPassword);
        }
    }

    @TestVisible
    private static SitePasswordChange sitePasswords = new SitePasswordChange();

    // Not cacheable: the page shows what is saved now, also right after a change
    @AuraEnabled
    public static Profile getProfile() {
        return profileOf(currentCustomer().Id, null);
    }

    // Saves the details on the customer's contact and on their login. The login gets a new email only when it differs:
    // Salesforce may then keep the old one until the customer confirms the new address (emailPending).
    @AuraEnabled
    public static Profile updateProfile(String firstName, String lastName, String email, String phoneCountryCode, String phoneNumber, String department) {
        User me = currentCustomer();
        String givenName = trimmed(firstName);
        String familyName = trimmed(lastName);
        String mail = trimmed(email);
        String code = trimmed(phoneCountryCode).removeStart('+').trim();
        String phone = trimmed(phoneNumber).replaceAll('[\\s-]', '');
        String dept = trimmed(department);
        if (String.isBlank(givenName)) {
            throw userError(FIRST_NAME_REQUIRED);
        }
        if (givenName.length() > MAX_FIRST_NAME) {
            throw userError(FIRST_NAME_TOO_LONG);
        }
        if (String.isBlank(familyName)) {
            throw userError(LAST_NAME_REQUIRED);
        }
        if (familyName.length() > MAX_LAST_NAME) {
            throw userError(LAST_NAME_TOO_LONG);
        }
        if (String.isBlank(mail)) {
            throw userError(EMAIL_REQUIRED);
        }
        if (mail.length() > MAX_EMAIL) {
            throw userError(EMAIL_TOO_LONG);
        }
        if (!EMAIL_PATTERN.matcher(mail).matches()) {
            throw userError(EMAIL_INVALID);
        }
        if (!COUNTRY_CODES.contains(code)) {
            throw userError(COUNTRY_CODE_INVALID);
        }
        if (String.isBlank(phone)) {
            throw userError(PHONE_REQUIRED);
        }
        if (!PHONE_DIGITS.matcher(phone).matches()) {
            throw userError(PHONE_INVALID);
        }
        if (dept.length() > MAX_DEPARTMENT) {
            throw userError(DEPARTMENT_TOO_LONG);
        }
        String mobile = '+' + code + ' ' + phone;

        Contact person = new Contact(
            Id = me.ContactId,
            FirstName = givenName,
            LastName = familyName,
            Email = mail,
            MobilePhone = mobile,
            Department = String.isBlank(dept) ? null : dept
        );
        // A customer correcting their own details is never stopped by a duplicate alert
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        person.setOptions(options);
        // Only these login fields: they may be saved together with the contact (no mixed DML)
        User login = new User(Id = me.Id, FirstName = givenName, LastName = familyName, MobilePhone = mobile);
        if (!mail.equalsIgnoreCase(me.Email)) {
            login.Email = mail;
        }
        Savepoint beforeSave = Database.setSavepoint();
        try {
            update as system person;
            update as system login;
        } catch (DmlException e) {
            Database.rollback(beforeSave);
            System.debug(LoggingLevel.ERROR, 'Customer Portal profile not saved: ' + dmlTypeOf(e) + ' ' + dmlFieldsOf(e));
            throw userError(dmlTypeOf(e) == StatusCode.INVALID_EMAIL_ADDRESS ? EMAIL_INVALID : PROFILE_NOT_SAVED);
        }
        return profileOf(me.Id, mail);
    }

    // Saves the picture as the account's profile picture file and points the account's field at it. base64Data is the
    // picture's Base64 text (a 'data:image/...;base64,' start is allowed); only JPEG and PNG pictures are taken.
    @AuraEnabled
    public static Profile uploadProfilePicture(String base64Data, String fileName, String contentType) {
        User me = currentCustomer();
        if (String.isBlank(base64Data)) {
            throw userError(PICTURE_REQUIRED);
        }
        if (!PICTURE_TYPES.contains(trimmed(contentType).toLowerCase())) {
            throw userError(PICTURE_WRONG_TYPE);
        }
        // The most Base64 text a picture of maxPictureBytes takes, checked before anything is copied or decoded
        Integer maxLength = ((maxPictureBytes + 2) / 3) * 4;
        if (base64Data.length() > maxLength + MAX_DATA_URL_PREFIX) {
            throw userError(PICTURE_TOO_BIG);
        }
        // The large values are let go as soon as they are not needed, so a big picture stays within the Apex heap
        String data = base64Data;
        base64Data = null;
        if (data.startsWith('data:')) {
            data = data.substringAfter(',');
        }
        if (String.isBlank(data)) {
            throw userError(PICTURE_REQUIRED);
        }
        if (data.length() > maxLength) {
            throw userError(PICTURE_TOO_BIG);
        }
        // What the bytes really are, whatever the name or type says
        String extension = imageExtension(data);
        if (extension == null) {
            throw userError(PICTURE_WRONG_TYPE);
        }
        Blob picture;
        try {
            picture = EncodingUtil.base64Decode(data);
        } catch (Exception e) {
            throw userError(PICTURE_WRONG_TYPE);
        }
        data = null;
        if (picture.size() > maxPictureBytes) {
            throw userError(PICTURE_TOO_BIG);
        }
        Id accountId = me.Contact.AccountId;
        Savepoint beforePicture = null;
        try {
            // One savepoint over both: a failed account update must not leave the file behind without the account
            // pointing at it
            beforePicture = Database.setSavepoint();
            Id documentId = savePicture(accountId, picture, fileNameFor(fileName, extension));
            update as system new Account(Id = accountId, Profile_Picture_Document_Id__c = documentId);
        } catch (DmlException e) {
            if (beforePicture != null) {
                Database.rollback(beforePicture);
            }
            System.debug(LoggingLevel.ERROR, 'Customer Portal profile picture not saved: ' + dmlTypeOf(e) + ' ' + dmlFieldsOf(e));
            throw userError(PICTURE_NOT_SAVED);
        }
        picture = null;
        return profileOf(me.Id, null);
    }

    // Changes the customer's password through the site, as Salesforce's own Change Password page does. The rules here are
    // the page's; Salesforce applies its password policy as well. The passwords are never logged.
    @AuraEnabled
    public static void changePassword(String oldPassword, String newPassword, String confirmPassword) {
        User me = currentCustomer();
        if (String.isBlank(oldPassword) || String.isBlank(newPassword) || String.isBlank(confirmPassword)) {
            throw userError(PASSWORD_REQUIRED);
        }
        if (!newPassword.equals(confirmPassword)) {
            throw userError(PASSWORD_MISMATCH);
        }
        if (newPassword.length() < MIN_PASSWORD || !LETTER.matcher(newPassword).find() || !DIGIT.matcher(newPassword).find()) {
            throw userError(PASSWORD_TOO_WEAK);
        }
        if (newPassword.equals(oldPassword)) {
            throw userError(PASSWORD_SAME);
        }
        Datetime changedBefore = lastPasswordChange(me.Id);
        PageReference answer;
        try {
            answer = sitePasswords.changePassword(newPassword, confirmPassword, oldPassword);
        } catch (Exception e) {
            System.debug(LoggingLevel.INFO, 'Customer Portal password not changed: ' + e.getTypeName() + ' '
                + withoutPasswords(e.getMessage(), new List<String>{ oldPassword, newPassword, confirmPassword }));
            throw userError(PASSWORD_NOT_CHANGED);
        }
        // Salesforce answers with the page to open next. Without one the password counts as changed only when the login
        // shows a new password change.
        if (answer == null && lastPasswordChange(me.Id) == changedBefore) {
            throw userError(PASSWORD_NOT_CHANGED);
        }
    }

    // The account's profile picture as a data: URL of its latest version, or null when it has none, the file is gone or
    // is larger than maxInlineBytes. Also used for the avatar in the portal's header (CustomerPortalController).
    public static String photoUrlFor(Id accountId) {
        if (accountId == null) {
            return null;
        }
        try {
            List<Account> accounts = [SELECT Profile_Picture_Document_Id__c FROM Account WHERE Id = :accountId WITH SYSTEM_MODE LIMIT 1];
            Id documentId = accounts.isEmpty() ? null : documentIdOf(accounts[0].Profile_Picture_Document_Id__c);
            // Only a file of this account: an Id typed into the field by mistake never shows another customer's file
            if (documentId == null || !isOnAccount(documentId, accountId)) {
                return null;
            }
            List<ContentVersion> latest = [
                SELECT Id, FileType, ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId = :documentId AND IsLatest = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (latest.isEmpty() || latest[0].ContentSize == null || latest[0].ContentSize > maxInlineBytes) {
                return null;
            }
            String mimeType = MIME_TYPES.get(trimmed(latest[0].FileType).toUpperCase());
            if (mimeType == null) {
                return null;
            }
            // The bytes are let go before the URL is put together: at most about 4 MB of heap for a 1.5 MB picture
            Blob bytes = [SELECT VersionData FROM ContentVersion WHERE Id = :latest[0].Id WITH SYSTEM_MODE LIMIT 1].VersionData;
            String encoded = EncodingUtil.base64Encode(bytes);
            bytes = null;
            return 'data:' + mimeType + ';base64,' + encoded;
        } catch (Exception e) {
            // The header and the page show the default avatar rather than fail
            System.debug(LoggingLevel.ERROR, 'Customer Portal profile picture not read: ' + e.getTypeName() + ' ' + e.getMessage());
            return null;
        }
    }

    // The signed-in customer's login with their contact and account; anybody else is refused
    private static User currentCustomer() {
        if (UserInfo.getUserType() == 'Guest') {
            throw userError(NOT_SIGNED_IN);
        }
        if (!CustomerPortalLoginController.isCustomer()) {
            throw userError(NOT_A_CUSTOMER);
        }
        return [SELECT Id, Email, ContactId, Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
    }

    // The page's data: the contact's details (the login's where the contact has none), the login's username and the
    // account's picture. requestedEmail is the email just saved, to tell whether the login still has its old one.
    private static Profile profileOf(Id userId, String requestedEmail) {
        User login = [
            SELECT Username, FirstName, LastName, Email, MobilePhone,
                Contact.FirstName, Contact.LastName, Contact.Email, Contact.MobilePhone, Contact.Department, Contact.AccountId
            FROM User
            WHERE Id = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Contact person = login.Contact;
        Profile result = new Profile();
        result.firstName = firstFilled(person.FirstName, login.FirstName);
        result.lastName = firstFilled(person.LastName, login.LastName);
        result.fullName = (trimmed(result.firstName) + ' ' + trimmed(result.lastName)).trim();
        result.email = firstFilled(person.Email, login.Email);
        List<String> phone = splitPhone(firstFilled(person.MobilePhone, login.MobilePhone));
        result.phoneCountryCode = phone[0];
        result.phoneNumber = phone[1];
        result.department = person.Department;
        result.username = login.Username;
        result.photoUrl = photoUrlFor(person.AccountId);
        result.hasPhoto = result.photoUrl != null;
        // Still waiting for confirmation: the contact already carries the new address while the login keeps the
        // confirmed one, so a reload still shows the note
        result.emailPending = (requestedEmail != null && !requestedEmail.equalsIgnoreCase(login.Email))
            || (String.isNotBlank(person.Email) && String.isNotBlank(login.Email) && !person.Email.equalsIgnoreCase(login.Email));
        return result;
    }

    // A new version of the account's picture file when it has one, otherwise a new file on the account; returns the
    // file's ContentDocument Id
    private static Id savePicture(Id accountId, Blob picture, String pathOnClient) {
        // The file belongs to the account's owner, as the Partner Portal registration saves its uploads. A file saved
        // by the community user itself is refused outside a site session (the platform stamps ContentVersion.NetworkId
        // from the membership: INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY: [NetworkId]).
        Id ownerId = [SELECT OwnerId FROM Account WHERE Id = :accountId WITH SYSTEM_MODE LIMIT 1].OwnerId;
        Id documentId = currentPictureId(accountId);
        if (documentId != null) {
            Savepoint beforeVersion = Database.setSavepoint();
            try {
                insert as system new ContentVersion(
                    ContentDocumentId = documentId,
                    Title = PICTURE_TITLE,
                    PathOnClient = pathOnClient,
                    VersionData = picture,
                    OwnerId = ownerId,
                    ReasonForChange = 'New profile picture from the Customer Portal'
                );
                ensureAccountLink(documentId, accountId);
                return documentId;
            } catch (DmlException e) {
                // For example a file somebody else owns that the customer may not change: a new file takes its place
                Database.rollback(beforeVersion);
                System.debug(LoggingLevel.WARN, 'Customer Portal profile picture: new file instead of a version of ' + documentId + ' (' + dmlTypeOf(e) + ')');
            }
        }
        // Saved on the account: Salesforce links the file to it
        ContentVersion firstVersion = new ContentVersion(
            Title = PICTURE_TITLE,
            PathOnClient = pathOnClient,
            VersionData = picture,
            FirstPublishLocationId = accountId,
            OwnerId = ownerId
        );
        // NetworkId is deliberately not set: a customer community user may not set it (INSUFFICIENT_ACCESS_ON_
        // CROSS_REFERENCE_ENTITY), and the file does not need it — the account link below makes it visible
        insert as system firstVersion;
        documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :firstVersion.Id WITH SYSTEM_MODE LIMIT 1].ContentDocumentId;
        ensureAccountLink(documentId, accountId);
        return documentId;
    }

    // The picture file the account points to, when that file still exists and belongs to the account
    private static Id currentPictureId(Id accountId) {
        Account account = [SELECT Profile_Picture_Document_Id__c FROM Account WHERE Id = :accountId WITH SYSTEM_MODE LIMIT 1];
        Id documentId = documentIdOf(account.Profile_Picture_Document_Id__c);
        if (documentId == null || !isOnAccount(documentId, accountId)) {
            return null;
        }
        return documentId;
    }

    // Whether the file is linked to the account (a deleted file has no links)
    private static Boolean isOnAccount(Id documentId, Id accountId) {
        return [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :documentId AND LinkedEntityId = :accountId
            WITH SYSTEM_MODE
        ] > 0;
    }

    // The account's link to the file as SHARE_VIEWER / VISIBLE_TO_ALL describe: made when it is missing, opened up to
    // customers when only internal users see it (internal users see it either way, so that change may fail quietly)
    @TestVisible
    private static void ensureAccountLink(Id documentId, Id accountId) {
        List<ContentDocumentLink> links = [
            SELECT Id, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :documentId AND LinkedEntityId = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (links.isEmpty()) {
            insert as system new ContentDocumentLink(
                ContentDocumentId = documentId,
                LinkedEntityId = accountId,
                ShareType = SHARE_VIEWER,
                Visibility = VISIBLE_TO_ALL
            );
        } else if (links[0].Visibility != VISIBLE_TO_ALL) {
            links[0].Visibility = VISIBLE_TO_ALL;
            try {
                update as system links[0];
            } catch (DmlException e) {
                System.debug(LoggingLevel.WARN, 'Customer Portal profile picture link not opened to customers: ' + dmlTypeOf(e));
            }
        }
    }

    // The ContentDocument Id in the account's field, or null for anything else
    private static Id documentIdOf(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Id documentId = Id.valueOf(value.trim());
            return documentId.getSObjectType() == ContentDocument.SObjectType ? documentId : null;
        } catch (Exception e) {
            return null;
        }
    }

    // 'jpg' or 'png' from the first bytes of the picture (FF D8 FF, or the PNG signature), otherwise null
    private static String imageExtension(String data) {
        if (data.startsWith('/9j/')) {
            return 'jpg';
        }
        if (data.startsWith('iVBORw0KGgo')) {
            return 'png';
        }
        return null;
    }

    // The name the file keeps in Salesforce: the customer's file name without folders or unusual characters, with the
    // extension of what was really sent (Salesforce takes the file type from it)
    @TestVisible
    private static String fileNameFor(String fileName, String extension) {
        String name = trimmed(fileName).left(255);
        if (name.contains('/')) {
            name = name.substringAfterLast('/');
        }
        if (name.contains('\\')) {
            name = name.substringAfterLast('\\');
        }
        if (name.contains('.')) {
            name = name.substringBeforeLast('.');
        }
        name = name.replaceAll('[^A-Za-z0-9 ._-]', '_').trim().left(80);
        return (String.isBlank(name) ? 'profile-picture' : name) + '.' + extension;
    }

    // { country code, number } from a saved Mobile: '+94 771234567' as this page saves it, a known code written without a
    // space, or '00' for '+'. Anything else is Sri Lanka's code with all the digits as the number.
    @TestVisible
    private static List<String> splitPhone(String value) {
        String phone = trimmed(value);
        if (phone.startsWith('00')) {
            phone = '+' + phone.substring(2);
        }
        if (phone.startsWith('+')) {
            Matcher withCode = PHONE_WITH_CODE.matcher(phone);
            if (withCode.matches()) {
                return COUNTRY_CODES.contains(withCode.group(1))
                    ? new List<String>{ withCode.group(1), digitsOf(withCode.group(2)) }
                    : new List<String>{ DEFAULT_COUNTRY_CODE, digitsOf(phone) };
            }
            String digits = digitsOf(phone);
            for (String code : COUNTRY_CODES) {
                if (digits.startsWith(code)) {
                    return new List<String>{ code, digits.substring(code.length()) };
                }
            }
        }
        return new List<String>{ DEFAULT_COUNTRY_CODE, digitsOf(phone) };
    }

    private static Datetime lastPasswordChange(Id userId) {
        return [SELECT LastPasswordChangeDate FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1].LastPasswordChangeDate;
    }

    // A message for the debug log with every password replaced
    private static String withoutPasswords(String message, List<String> passwords) {
        String text = message == null ? '' : message;
        for (String password : passwords) {
            if (String.isNotEmpty(password)) {
                text = text.replace(password, '***');
            }
        }
        return text;
    }

    // The failure Salesforce reported for the first row; a DmlException without rows (a mixed DML message, say) would
    // make getDmlType(0) throw, which would hide the message the page is about to show
    private static StatusCode dmlTypeOf(DmlException e) {
        return e.getNumDml() > 0 ? e.getDmlType(0) : null;
    }

    private static List<String> dmlFieldsOf(DmlException e) {
        return e.getNumDml() > 0 ? e.getDmlFieldNames(0) : new List<String>();
    }

    private static String digitsOf(String value) {
        return value == null ? '' : value.replaceAll('[^0-9]', '');
    }

    private static String firstFilled(String preferred, String fallback) {
        return String.isNotBlank(preferred) ? preferred : fallback;
    }

    private static String trimmed(String value) {
        return value == null ? '' : value.trim();
    }

    // AuraHandledException only exposes its text to Apex callers (and tests) when setMessage is also called
    private static AuraHandledException userError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    // ======================================================================================================
    // PROJECTS PAGE (was CustomerPortalProjectController, merged 2026-10-19)
    // ======================================================================================================

    // Messages this class shows or sends
    @TestVisible private static final String CUSTOMER_PORTAL_LOGIN_REQUIRED = 'Please log in to the portal to see the projects.';


    // Active projects with the photos of their "Project Images" folder
    @AuraEnabled
    public static List<partnerWebPortalMarketingController.ProjectCard> getProjects() {
        requireLogin();
        return partnerWebPortalMarketingController.cardsFor([
            SELECT Id, Name, Project_Location__c
            FROM Project__c
            WHERE Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 50
        ]);
    }

    // The whole page of an active project: photos, amenities, configurations with their price sheets, documents
    @AuraEnabled
    public static partnerWebPortalMarketingController.ProjectDetail getProjectDetails(Id projectId) {
        requireLogin();
        return partnerWebPortalMarketingController.detailsOf(projectId);
    }

    private static void requireLogin() {
        if (isGuest()) {
            throw userError(CUSTOMER_PORTAL_LOGIN_REQUIRED);
        }
    }

    // Tests set this to act as a guest or as a logged-in user
    @TestVisible
    private static Boolean guestOverride;

    private static Boolean isGuest() {
        return guestOverride != null ? guestOverride : UserInfo.getUserType() == 'Guest';
    }

}