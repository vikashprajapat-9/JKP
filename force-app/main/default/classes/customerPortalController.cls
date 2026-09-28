public with sharing class customerPortalController {

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

    public class ProfileData {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public String phoneCountryCode;
        @AuraEnabled public String phoneNumber;
        @AuraEnabled public String department;
        @AuraEnabled public String username;
        @AuraEnabled public String password;
        @AuraEnabled public String avatarUrl;
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


    @AuraEnabled(cacheable=true)
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

    @AuraEnabled(cacheable=true)
    public static HeaderData getHeaderData() {
        HeaderData data = new HeaderData();
        data.userName = 'Vikash Prajapat';
        data.userRole = 'Customer';
        data.avatarUrl = null; 
        data.notificationCount = 3;
        return data;
    }

    @AuraEnabled(cacheable=true)
    public static ProfileData getProfileData() {
        ProfileData data = new ProfileData();
        data.firstName = 'John';
        data.lastName = 'Doe';
        data.fullName = 'John Doe';
        data.email = 'john@gmail.com';
        data.phoneCountryCode = '94';
        data.phoneNumber = '9876543210';
        data.department = 'Sales';
        data.username = 'John';
        data.password = '********';
        data.avatarUrl = null;
        return data;
    }

    @AuraEnabled(cacheable=true)
    public static List<Project> getProjects() {
        return buildProjects();
    }

    @AuraEnabled(cacheable=true)
    public static Project getProjectDetails(String projectId) {
        for (Project p : buildProjects()) {
            if (p.id == projectId) {
                return p;
            }
        }
        return null;
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

    public class ReferralRecord {
        @AuraEnabled public String id;
        @AuraEnabled public String propertyName;
        @AuraEnabled public String friendName;
        @AuraEnabled public String emailId;
        @AuraEnabled public String mobileNumber;
        @AuraEnabled public String status;
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

    @AuraEnabled(cacheable=true)
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

    @AuraEnabled
    public static ReferralSuccessData sendReferral(String propertyName, String friendName, String mobileNumber) {
        if (String.isBlank(propertyName) || String.isBlank(friendName) || String.isBlank(mobileNumber)) {
            throw new AuraHandledException('Property, friend name and mobile number are required.');
        }

        // insert new Referral__c(
        //     Property__c = propertyName,
        //     Friend_Name__c = friendName,
        //     Mobile_Number__c = mobileNumber,
        //     Status__c = 'Pending'
        // );

        return buildSuccessData();
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

    private static List<PropertyOption> buildPropertyOptions() {
        List<PropertyOption> options = new List<PropertyOption>();
        options.add(buildOption('JK Kingsland', 'JK Kingsland'));
        options.add(buildOption('JK Monarch', 'JK Monarch'));
        options.add(buildOption('JK Elements', 'JK Elements'));
        return options;
    }

    private static PropertyOption buildOption(String label, String value) {
        PropertyOption opt = new PropertyOption();
        opt.label = label;
        opt.value = value;
        return opt;
    }

    private static List<ReferralRecord> buildReferrals() {
        List<ReferralRecord> records = new List<ReferralRecord>();

        records.add(buildReferral('1', 'Tri-Zen Apartments', 'Mohan Kumar', 'mohankuamr@gmail.com', '+94 71 *** ****', 'Booked'));
        records.add(buildReferral('2', 'Tri-Zen Apartments', 'Kavita P', 'kavitaP@gmail.com', '+94 81 *** ****', 'Not booked'));

        return records;
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
 
        data.projectFilters = new List<PropertyOption>{
            buildOption('JK Pallaciya', 'JK Pallaciya'),
            buildOption('JK Kingsland', 'JK Kingsland'),
            buildOption('Savera Residency', 'Savera Residency')
        };
 
        data.properties = buildMyProperties();
 
        return data;
    }
 
    private static List<MyProperty> buildMyProperties() {
        List<MyProperty> properties = new List<MyProperty>();
        properties.add(buildJkKingslandProperty());
        properties.add(buildSaveraResidencyProperty());
        return properties;
    }
 
    private static MyProperty buildJkKingslandProperty() {
        MyProperty prop = new MyProperty();
        prop.id = 'MYPROP-001';
        prop.projectName = 'JK Kingsland';
        prop.description = 'JK Kingsland';
        prop.unitNumber = 'B2-210';
        prop.carParks = '2';
        prop.type = '2 BHK';
 
        Applicant a1 = new Applicant();
        a1.name = 'Nimal Perera';
        a1.applicantType = 'First Applicant';
        a1.dateOfBirth = '23-10-1994';
        a1.mobileNumber = '+94 71 *** ****';
        a1.email = 'nirmalperera@gmail.com';
        a1.address = 'No. 24, Flower Road, Colombo 07, Sri Lanka';
        a1.nic = '199845612345';
        a1.tin = 'TIN-456789123';
        a1.passport = 'P9876543';
 
        Applicant a2 = new Applicant();
        a2.name = 'Sanduni Jayasinghe';
        a2.applicantType = 'Second Applicant';
        a2.companyName = 'ULabs Pvt.Ltd';
        a2.mobileNumber = '+94 71 *** ****';
        a2.email = 'sanduni@Ulabs.com';
        a2.address = 'No. 24, Flower Road, Colombo 07, Sri Lanka';
        a2.vatNumber = '123456789';
        a2.businessRegistrationNumber = '199845612345';
 
        prop.applicants = new List<Applicant>{ a1, a2 };
 
        BankDetails bank = new BankDetails();
        bank.accountName = 'Nimal Perera';
        bank.accountNo = '1234567890';
        bank.bankName = 'Commercial Bank of Ceylon PLC';
        bank.branchName = 'Colombo 01 Branch';
        bank.swiftCode = 'CCEYLKLX';
 
        BookingDetail booking = new BookingDetail();
        booking.id = 'BOOK-001';
        booking.description = 'JK Kingsland';
        booking.unitNumber = 'B2-210';
        booking.carParks = '2';
        booking.type = '2 BHK';
        booking.spaDate = '12/06/2024';
        booking.flatVilla = 'Flat';
        booking.towerBlockVilla = 'Block B';
        booking.squareFeet = '1235';
        booking.purchasedPrice = 'LKR 2,11,69,460.00';
        booking.escrowAccountNumber = '1889089787828UP';
        booking.bankDetails = bank;
 
        prop.bookingDetails = new List<BookingDetail>{ booking };
 
        PaymentPlanRow row1 = new PaymentPlanRow();
        row1.description = 'Token amount towards application for Sale';
        row1.percentage = '5';
        row1.trancheDate = '20/08/2026';
        row1.amount = 'LKR 540,667.00';
 
        PaymentPlanRow row2 = new PaymentPlanRow();
        row2.description = '10% on completion of excavation';
        row2.percentage = '20';
        row2.trancheDate = '21/09/2026';
        row2.amount = 'LKR 540,667.00';
 
        PaymentPlanRow row3 = new PaymentPlanRow();
        row3.description = '10% on completion of Ground floor slab';
        row3.percentage = '65';
        row3.trancheDate = '21/10/2026';
        row3.amount = 'LKR 540,667.00';
 
        prop.paymentPlan = new List<PaymentPlanRow>{ row1, row2, row3 };
        prop.paymentPlanTotal = 'LKR 90,088,034';
 
        return prop;
    }
 
    private static MyProperty buildSaveraResidencyProperty() {
        MyProperty prop = new MyProperty();
        prop.id = 'MYPROP-002';
        prop.projectName = 'Savera Residency';
        prop.description = 'Savera Residency';
        prop.unitNumber = 'B3-310';
        prop.carParks = '2';
        prop.type = '2 BHK';
 
        Applicant a1 = new Applicant();
        a1.name = 'Kasun Fernando';
        a1.applicantType = 'First Applicant';
        a1.dateOfBirth = '14-02-1990';
        a1.mobileNumber = '+94 77 *** ****';
        a1.email = 'kasunf@gmail.com';
        a1.address = 'No. 8, Lake Drive, Colombo 05, Sri Lanka';
        a1.nic = '199012345678';
        a1.tin = 'TIN-321654987';
        a1.passport = 'P1122334';
 
        prop.applicants = new List<Applicant>{ a1 };
 
        BankDetails bank = new BankDetails();
        bank.accountName = 'Kasun Fernando';
        bank.accountNo = '9988776655';
        bank.bankName = 'Sampath Bank PLC';
        bank.branchName = 'Colombo 05 Branch';
        bank.swiftCode = 'BSAMLKLX';
 
        BookingDetail booking = new BookingDetail();
        booking.id = 'BOOK-002';
        booking.description = 'Savera Residency';
        booking.unitNumber = 'B3-310';
        booking.carParks = '2';
        booking.type = '2 BHK';
        booking.spaDate = '05/09/2024';
        booking.flatVilla = 'Flat';
        booking.towerBlockVilla = 'Block C';
        booking.squareFeet = '1180';
        booking.purchasedPrice = 'LKR 1,95,40,000.00';
        booking.escrowAccountNumber = '2299887766554UP';
        booking.bankDetails = bank;
 
        prop.bookingDetails = new List<BookingDetail>{ booking };
 
        PaymentPlanRow row1 = new PaymentPlanRow();
        row1.description = 'Token amount towards application for Sale';
        row1.percentage = '5';
        row1.trancheDate = '15/09/2026';
        row1.amount = 'LKR 500,000.00';
 
        PaymentPlanRow row2 = new PaymentPlanRow();
        row2.description = '10% on completion of excavation';
        row2.percentage = '20';
        row2.trancheDate = '15/10/2026';
        row2.amount = 'LKR 500,000.00';
 
        prop.paymentPlan = new List<PaymentPlanRow>{ row1, row2 };
        prop.paymentPlanTotal = 'LKR 19,540,000';
 
        return prop;
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

     public class SupportIssueOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Boolean requiresDetails; 
    }

    public class SupportServiceRequest {
        @AuraEnabled public String id;
        @AuraEnabled public String serviceRequestId;
        @AuraEnabled public String description;
        @AuraEnabled public String projectName;
        @AuraEnabled public String propertyName;
        @AuraEnabled public String type;
        @AuraEnabled public String status; 
        @AuraEnabled public String createdDate;
    }

    public class SupportPageData {
        @AuraEnabled public String description;
        @AuraEnabled public String dlpLabel;
        @AuraEnabled public String dlpStartDate;
        @AuraEnabled public String dlpEndDate;
        @AuraEnabled public List<SupportServiceRequest> serviceRequests;
        @AuraEnabled public List<PropertyOption> projectFilters;   
        @AuraEnabled public List<SupportIssueOption> issueOptions;
        @AuraEnabled public List<PropertyOption> propertyOptions;
        @AuraEnabled public String emptyStateImageUrl;
    }

    public class SupportActionResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public String serviceRequestId;
    }

    @AuraEnabled(cacheable=true)
    public static SupportPageData getSupportPageData() {
        try {
            SupportPageData data = new SupportPageData();

            data.description = 'Manage your support tickets with John Keels Properties . by viewing or raising them '
                + 'below. Stay informed on your inquiries, access details of ongoing support issues, and respond '
                + 'promptly to updates. Our team is dedicated to providing you with effective support. For any '
                + 'questions or additional assistance, please don\u2019t hesitate to contact our support team.';

            data.dlpStartDate = '20/09/2026';
            data.dlpEndDate = '20/09/2027';
            data.dlpLabel = 'Defects Liability Period(DLP): ' + data.dlpStartDate + '-' + data.dlpEndDate;

            data.serviceRequests = new List<SupportServiceRequest>{
                buildServiceRequest('SR-001', 'SDFG5', 'Garbage Not Being Disposed Properly in our locality', 'The Monarch', 'Maintenance', 'Pending', '15/09/2026'),
                buildServiceRequest('SR-002', 'SDFG5', 'Lights not working on the floor.', 'JK Kingsland', 'Maintenance', 'Resolved', '10/09/2026'),
                buildServiceRequest('SR-003', 'SDFG7', 'Garbage Not Being Disposed Properly in our locality', 'JK Pallaciya', 'Maintenance', 'Pending', '18/09/2026')
            };

            data.projectFilters = new List<PropertyOption>{
                buildOption('All Projects', ''),
                buildOption('The Monarch', 'The Monarch'),
                buildOption('JK Kingsland', 'JK Kingsland'),
                buildOption('JK Pallaciya', 'JK Pallaciya')
            };

            data.propertyOptions = new List<PropertyOption>{
                buildOption('The Monarch', 'The Monarch'),
                buildOption('JK Kingsland', 'JK Kingsland'),
                buildOption('JK Pallaciya', 'JK Pallaciya')
            };

            data.issueOptions = new List<SupportIssueOption>{
                buildIssueOption('Maintenance', 'Maintenance', false),
                buildIssueOption('Payment', 'Payment', false),
                buildIssueOption('Property', 'Property', false),
                buildIssueOption('Documentation', 'Documentation', false),
                buildIssueOption('Others', 'Others', true)
            };

            data.emptyStateImageUrl = '/resource/SupportEmptyState';

            return data;
        } catch (Exception e) {
            throw buildAuraException('Unable to load support data: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static SupportActionResponse createServiceRequest(String issueType,String propertyName,String unitNumber,String otherDetails,String description) {
        if (String.isBlank(issueType) || String.isBlank(propertyName)
            || String.isBlank(unitNumber) || String.isBlank(description)) {
            throw buildAuraException('Issue, property, unit number and description are required.');
        }
        if (issueType == 'Others' && String.isBlank(otherDetails)) {
            throw buildAuraException('Please specify the issue.');
        }

        try {
           
            // Service_Request__c sr = new Service_Request__c(
            //     Issue_Type__c    = issueType,
            //     Property__c      = propertyName,
            //     Unit_Number__c   = unitNumber,
            //     Other_Details__c = otherDetails,
            //     Description__c   = description,
            //     Status__c        = 'Pending'
            // );
            // insert sr;

            SupportActionResponse response = new SupportActionResponse();
            response.success = true;
            response.title = 'Your service request has been raised!';
            response.message = 'We have received your service request and it is now being reviewed by our team. '
                + 'You will receive a response shortly. Thank you for contacting John Keells Properties . '
                + 'For any questions or assistance, please don\u2019t hesitate to contact our support team.';
            response.serviceRequestId = null; // will hold the new record Id once DML is implemented
            return response;
        } catch (Exception e) {
            throw buildAuraException('Unable to raise the service request: ' + e.getMessage());
        }
    }

    private static SupportServiceRequest buildServiceRequest(String id, String serviceRequestId, String description,String projectName, String type, String status, String createdDate) {
        SupportServiceRequest sr = new SupportServiceRequest();
        sr.id = id;
        sr.serviceRequestId = serviceRequestId;
        sr.description = description;
        sr.projectName = projectName;
        sr.propertyName = projectName;
        sr.type = type;
        sr.status = status;
        sr.createdDate = createdDate;
        return sr;
    }

    private static SupportIssueOption buildIssueOption(String label, String value, Boolean requiresDetails) {
        SupportIssueOption opt = new SupportIssueOption();
        opt.label = label;
        opt.value = value;
        opt.requiresDetails = requiresDetails;
        return opt;
    }

     public class EventWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String eventDate;
        @AuraEnabled public String startTime;
        @AuraEnabled public String endTime;
        @AuraEnabled public String location;
        @AuraEnabled public String iconUrl;
        @AuraEnabled public Boolean isRegistered;
    }

    public class EventRegistrationResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Boolean isRegistered;
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public String eventId;
    }

    @AuraEnabled(cacheable=true)
    public static List<EventWrapper> getEvents() {
        try {
            List<EventWrapper> events = new List<EventWrapper>();

            events.add(buildEvent(
                'EVT-001',
                'Real Estate Summit 2025',
                'Join top industry experts for insights on the latest trends.',
                'Sep 15, 2025', '10:00 AM', '3:00 PM', 'WTC,Colombo',
                'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=200',
                false
            ));

            events.add(buildEvent(
                'EVT-002',
                'Property Investment Conference',
                'Learn how to build a resilient property portfolio from leading investors.',
                'Oct 03, 2025', '9:30 AM', '1:30 PM', 'Shangri-La Hotel, Colombo',
                'https://images.unsplash.com/photo-1511578314322-379afb476865?w=200',
                false
            ));

            events.add(buildEvent(
                'EVT-003',
                'Homeowners Networking Evening',
                'Meet fellow homeowners and the John Keells Properties team over an evening of networking.',
                'Oct 21, 2025', '5:00 PM', '8:00 PM', 'Cinnamon Life, Colombo',
                'https://images.unsplash.com/photo-1505373877841-8d25f7d46678?w=200',
                false
            ));

            return events;
        } catch (Exception e) {
            throw buildAuraException('Unable to load events: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static EventRegistrationResponse registerForEvent(String eventId,String eventTitle,String eventDate,String startTime,String endTime,String eventLocation) {
        if (String.isBlank(eventId) || String.isBlank(eventTitle)) {
            throw buildAuraException('Event id and title are required.');
        }

        try {

            EventRegistrationResponse response = new EventRegistrationResponse();
            response.success = true;
            response.isRegistered = true;
            response.title = 'Registration Successful';
            response.message = 'You have been registered for this event.';
            response.eventId = eventId;
            return response;
        } catch (Exception e) {
            throw buildAuraException('Unable to register for the event: ' + e.getMessage());
        }
    }

    private static EventWrapper buildEvent(String id, String title, String description,String eventDate, String startTime, String endTime,String location, String iconUrl, Boolean isRegistered) {
        EventWrapper ev = new EventWrapper();
        ev.id = id;
        ev.title = title;
        ev.description = description;
        ev.eventDate = eventDate;
        ev.startTime = startTime;
        ev.endTime = endTime;
        ev.location = location;
        ev.iconUrl = iconUrl;
        ev.isRegistered = isRegistered;
        return ev;
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

    private static List<FAQCategory> buildFaqCategories() {
        List<FAQCategory> categories = new List<FAQCategory>();
        categories.add(buildBillingCategory());
        categories.add(buildAgreementCategory());
        categories.add(buildHomeLoanCategory());
        return categories;
    }

    private static FAQCategory buildBillingCategory() {
        FAQCategory cat = new FAQCategory();
        cat.key = 'billing';
        cat.label = 'Billing';
        cat.faqs = new List<FAQItem>{
            buildFaqItem('billing-1', 1,
                'How can I schedule a property viewing?',
                'You can reach out to us via our contact form on the website, by phone, or by visiting our office during business hours to schedule a property viewing at your convenience.'),
            buildFaqItem('billing-2', 2,
                'Can I reschedule or cancel a property viewing?',
                'Yes, you can reschedule or cancel a scheduled viewing by contacting our support team at least 24 hours in advance so we can adjust the appointment accordingly.'),
            buildFaqItem('billing-3', 3,
                'What should I do if I have an issue with my rental property?',
                'Please raise a service request through the Support section of the portal, or contact our team directly, and we will address the issue as quickly as possible.'),
            buildFaqItem('billing-4', 4,
                'How can I get in touch with John Keels Properties for further assistance?',
                'You can reach out to us via our contact form on the website, by phone, or by visiting our office during business hours.')
        };
        return cat;
    }

    private static FAQCategory buildAgreementCategory() {
        FAQCategory cat = new FAQCategory();
        cat.key = 'agreement';
        cat.label = 'Agreement';
        cat.faqs = new List<FAQItem>{
            buildFaqItem('agreement-1', 1,
                'How do I obtain a copy of my sale agreement?',
                'A digital copy of your signed sale agreement is available under My Documents. You may also request a physical copy from our customer service team.'),
            buildFaqItem('agreement-2', 2,
                'What documents are required before signing the agreement?',
                'You will typically need valid identification, proof of address, and any applicable financing pre-approval documents. Our team will confirm the exact list for your booking.'),
            buildFaqItem('agreement-3', 3,
                'Can the terms of the agreement be amended after signing?',
                'Any amendments must be agreed upon in writing by both parties and documented as an addendum to the original agreement. Please contact our legal team for assistance.'),
            buildFaqItem('agreement-4', 4,
                'Who do I contact regarding agreement-related queries?',
                'For any questions about your agreement, please reach out to our customer support team, who will connect you with the relevant department.')
        };
        return cat;
    }

    private static FAQCategory buildHomeLoanCategory() {
        FAQCategory cat = new FAQCategory();
        cat.key = 'homeLoan';
        cat.label = 'Home Loan';
        cat.faqs = new List<FAQItem>{
            buildFaqItem('homeloan-1', 1,
                'Does John Keels Properties assist with home loan financing?',
                'Yes, we work with a panel of partner banks who can guide you through the home loan application process and offer preferential rates for our customers.'),
            buildFaqItem('homeloan-2', 2,
                'What documents are needed for a home loan application?',
                'Typically you will need proof of income, bank statements, identification documents and the sale agreement. Requirements vary slightly by bank.'),
            buildFaqItem('homeloan-3', 3,
                'How long does loan approval usually take?',
                'Approval timelines vary by bank, but most pre-approvals are processed within 2 to 4 weeks once all required documentation has been submitted.'),
            buildFaqItem('homeloan-4', 4,
                'Can I change my financing bank after booking?',
                'Yes, you may switch your financing bank at any point before final disbursement, provided you inform our sales team so the necessary paperwork can be updated.')
        };
        return cat;
    }

    private static FAQItem buildFaqItem(String id, Integer displayOrder, String question, String answer) {
        FAQItem item = new FAQItem();
        item.id = id;
        item.displayOrder = displayOrder;
        item.question = question;
        item.answer = answer;
        return item;
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
    }

    @AuraEnabled(cacheable=true)
    public static SimplePageData getAboutUsData() {
        try {
            SimplePageData data = new SimplePageData();
            data.title = 'About Us';
            data.description = 'Update your personal information, manage preferences on your John Keels '
                + 'Properties . profile dashboard.';
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

    public class LetsTalkProject {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String propertyAddress;
        @AuraEnabled public String propertyMapUrl;
        @AuraEnabled public String email;
        @AuraEnabled public String emailUrl;
        @AuraEnabled public String crmContact;
        @AuraEnabled public String phone;
        @AuraEnabled public String phoneUrl;
        @AuraEnabled public String corporateAddress;
        @AuraEnabled public String corporateMapUrl;
    }
    
    public class LetsTalkPageData {
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String defaultProject;
        @AuraEnabled public List<LetsTalkProject> projects;
    }
    
    @AuraEnabled(cacheable=true)
    public static LetsTalkPageData getLetsTalkPageData() {
        try {
            LetsTalkPageData data = new LetsTalkPageData();
    
            data.title = 'Let\u2019s Talk';
            data.description = 'Get in touch with John Keells Properties for any questions, assistance, or '
                + 'support you may need. Find the right contact details for your property, reach our team by '
                + 'email or phone, or locate our offices on the map. We\u2019re here to help and ensure you have '
                + 'a smooth and hassle-free experience. For any specific inquiries, please feel free to reach '
                + 'out to our team.';
    
            data.projects = buildLetsTalkProjects();
            data.defaultProject = 'LT-MONARCH';
    
            return data;
        } catch (Exception e) {
            throw buildAuraException('Unable to load Lets Talk data: ' + e.getMessage());
        }
    }
    
    private static List<LetsTalkProject> buildLetsTalkProjects() {
        List<LetsTalkProject> projects = new List<LetsTalkProject>();
    
        projects.add(buildLetsTalkProject(
            'LT-MONARCH', 'The Monarch',
            'John Keells Properties, No 186, Vauxhall Street, Colombo, Sri Lanka.',
            'https://maps.google.com/?q=John+Keells+Properties+Vauxhall+Street+Colombo',
            'customer.support@JKProperties.com',
            'Sai Krishna : +94 9100434848',
            '+94 9100434848',
            'John Keells Properties, No 186, Vauxhall Street, Colombo, Sri Lanka.',
            'https://maps.google.com/?q=John+Keells+Properties+Vauxhall+Street+Colombo'
        ));
    
        projects.add(buildLetsTalkProject(
            'LT-KINGSLAND', 'JK Kingsland',
            'Plot No-15, VIP Colony, Nayapally, Bhubaneswar.',
            'https://maps.google.com/?q=JK+Kingsland+Nayapally+Bhubaneswar',
            'kingsland.support@JKProperties.com',
            'Amal Perera : +94 7712345678',
            '+94 7712345678',
            'John Keells Properties, No 186, Vauxhall Street, Colombo, Sri Lanka.',
            'https://maps.google.com/?q=John+Keells+Properties+Vauxhall+Street+Colombo'
        ));
    
        projects.add(buildLetsTalkProject(
            'LT-PALLACIYA', 'JK Pallaciya',
            'Plot No-15, VIP Colony, Nayapally, Bhubaneswar.',
            'https://maps.google.com/?q=JK+Pallaciya+Nayapally+Bhubaneswar',
            'pallaciya.support@JKProperties.com',
            'Nadeesha Silva : +94 7798765432',
            '+94 7798765432',
            'John Keells Properties, No 186, Vauxhall Street, Colombo, Sri Lanka.',
            'https://maps.google.com/?q=John+Keells+Properties+Vauxhall+Street+Colombo'
        ));
    
        projects.add(buildLetsTalkProject(
            'LT-VIPULGARDENS', 'Vipul Gardens',
            'Plot No-15, VIP Colony, Nayapally, Bhubaneswar.',
            'https://maps.google.com/?q=Vipul+Gardens+Nayapally+Bhubaneswar',
            'vipulgardens.support@JKProperties.com',
            'Ruwan Fernando : +94 7711223344',
            '+94 7711223344',
            'John Keells Properties, No 186, Vauxhall Street, Colombo, Sri Lanka.',
            'https://maps.google.com/?q=John+Keells+Properties+Vauxhall+Street+Colombo'
        ));
    
        return projects;
    }
    
    private static LetsTalkProject buildLetsTalkProject(String id, String name,String propertyAddress, String propertyMapUrl,String email,String crmContact, String phone,String corporateAddress, String corporateMapUrl) {
        LetsTalkProject p = new LetsTalkProject();
        p.id = id;
        p.name = name;
        p.propertyAddress = propertyAddress;
        p.propertyMapUrl = propertyMapUrl;
        p.email = email;
        p.emailUrl = 'mailto:' + email;
        p.crmContact = crmContact;
        p.phone = phone;
        p.phoneUrl = 'tel:' + phone.replaceAll('[^+0-9]', '');
        p.corporateAddress = corporateAddress;
        p.corporateMapUrl = corporateMapUrl;
        return p;
    }
}