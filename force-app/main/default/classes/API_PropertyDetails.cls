@RestResource(urlMapping='/api/v1/properties/*')
global without sharing class API_PropertyDetails {

    @HttpGet
    global static void getPropertyDetails() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            PropertyDetailsResponse result = buildPropertyDetailsResponse(request);
            response.statusCode   = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('Error in API_PropertyDetails.getPropertyDetails ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_PropertyDetails', 'getPropertyDetails', e, null, 'SFA - SFDC');
            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(createResponse(false, 500, 'An unexpected error occurred while retrieving property details', null)));
        }
    }

    private static PropertyDetailsResponse buildPropertyDetailsResponse(RestRequest request) {
        try {
            String unitId = request != null && request.params != null? request.params.get('unitId'): null;
            unitId = unitId != null ? unitId.trim() : null;

            if (String.isBlank(unitId)) {
                return createResponse(false, 400, 'unitId is required', null);
            }

             String userId = UserInfo.getUserId();
            userId = userId != null ? userId.trim() : null;

            List<User> userList = [Select Id , Contact.AccountId from user where Id =: userId Limit 1 ];

            return getPropertyDetailsData(unitId , userList[0].Contact.AccountId);
        } catch (Exception e) {
            System.debug('Error in API_PropertyDetails.buildPropertyDetailsResponse ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_PropertyDetails', 'buildPropertyDetailsResponse', e, null, 'SFA - SFDC');
            return createResponse(false, 500, 'An unexpected error occurred while retrieving property details', null);
        }
    }

    private static PropertyDetailsResponse getPropertyDetailsData(String unitId , String acc) {
        List<Unit__c> matchedUnits = [SELECT Id, Name, Unit_Name_Code__c, Unit_Type__c, Salable_Area_sqft__c, Default_Parking__c,Floor__r.Block__r.Name,Floor__r.Block__r.Project__r.Name FROM Unit__c WHERE Id = :unitId OR Unit_Name_Code__c = :unitId WITH SYSTEM_MODE ORDER BY CreatedDate ASC LIMIT 1];
        if (matchedUnits.isEmpty()) {
            return createResponse(false, 404, 'Property not found', null);
        }
        Unit__c unit = matchedUnits[0];

        List<Opportunity> matchedOpportunities = [SELECT Id, Name, Amount, SPA_Signed_Date__c, Project__r.Name FROM Opportunity WHERE Unit__c = :unit.Id and AccountId =: acc WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1];
        Opportunity opportunity = matchedOpportunities.isEmpty() ? null : matchedOpportunities[0];
        String currencyCode = opportunity != null ? 'LKR' : null;

        Set<Id> opportunityIds = new Set<Id>();
        if (opportunity != null) {
            opportunityIds.add(opportunity.Id);
        }

        List<Applicant__c> applicantRecords = new List<Applicant__c>();
        List<Cost_Sheet_Payment_Schedule__c> scheduleRecords = new List<Cost_Sheet_Payment_Schedule__c>();
        if (!opportunityIds.isEmpty()) {
            applicantRecords = [SELECT Id, Name, IsPrimary__c, Account__r.Name FROM Applicant__c WHERE Opportunity__c IN :opportunityIds WITH SYSTEM_MODE ORDER BY CreatedDate ASC];
            scheduleRecords = [SELECT Id, Name, Description__c, Installment__c, Pay_Date__c, Due_Date__c,Installment_Sequence__c, Total_Amount_Inclusive_Of_Tax__c FROM Cost_Sheet_Payment_Schedule__c WHERE Opportunity__c IN :opportunityIds WITH SYSTEM_MODE ORDER BY Installment_Sequence__c ASC NULLS LAST, CreatedDate ASC];
        }

        List<Escrow_Account__c> escrowRecords = [SELECT Id, Name, Status__c FROM Escrow_Account__c WHERE (Unit__c = :unit.Id OR Opportunity__c IN :opportunityIds) AND Status__c = true WITH SYSTEM_MODE ORDER BY CreatedDate DESC];

        Project__c unitProject = unit.Floor__r != null && unit.Floor__r.Block__r != null? unit.Floor__r.Block__r.Project__r: null;
        String projectName = opportunity != null && opportunity.Project__r != null && opportunity.Project__r.Name != null? opportunity.Project__r.Name: (unitProject != null ? unitProject.Name : null);

        PaymentPlanWrapper paymentPlan = buildPaymentPlan(scheduleRecords, currencyCode);

        PropertyDetailsData detailsData = new PropertyDetailsData();
        detailsData.unitId     = unitId;
        detailsData.propertyName   = projectName;
        detailsData.salesOrderNo   = null;
        detailsData.applicants     = buildApplicants(applicantRecords);
        detailsData.paymentPlan    = paymentPlan;
        detailsData.bookingDetails = buildBookingDetails(unit, opportunity, escrowRecords, paymentPlan, currencyCode);

        return createResponse(true, 200, 'Property details retrieved successfully', detailsData);
    }

    private static List<ApplicantWrapper> buildApplicants(List<Applicant__c> applicantRecords) {
        List<ApplicantWrapper> applicants = new List<ApplicantWrapper>();
        for (Integer index = 0; index < applicantRecords.size(); index++) {
            Applicant__c applicantRecord = applicantRecords[index];

            ApplicantWrapper applicantItem = new ApplicantWrapper();
            applicantItem.applicantId   = String.isNotBlank(applicantRecord.Name) ? applicantRecord.Name : String.valueOf(applicantRecord.Id);
            // applicantItem.applicantId   = String.isNotBlank(applicantRecord.Id) ? applicantRecord.Id: String.valueOf(applicantRecord.Name);
            applicantItem.applicantType = buildApplicantType(index + 1);
            applicantItem.fullName      = applicantRecord.Account__c != null ? applicantRecord.Account__r.Name : null;
            applicantItem.isPrimary     = applicantRecord.IsPrimary__c;
            applicants.add(applicantItem);
        }
        return applicants;
    }

    private static final List<String> ORDINAL_WORDS = new List<String>{
        'First', 'Second', 'Third', 'Fourth', 'Fifth', 'Sixth', 'Seventh', 'Eighth', 'Ninth', 'Tenth'
    };

    private static String buildApplicantType(Integer position) {
        String ordinalWord = position >= 1 && position <= ORDINAL_WORDS.size()? ORDINAL_WORDS[position - 1]: position + numericSuffix(position);
        return ordinalWord + ' Applicant';
    }

    private static String numericSuffix(Integer position) {
        Integer lastTwoDigits = Math.mod(position, 100);
        Integer lastDigit     = Math.mod(position, 10);
        return (lastTwoDigits >= 11 && lastTwoDigits <= 13) ? 'th'
            : lastDigit == 1 ? 'st'
            : lastDigit == 2 ? 'nd'
            : lastDigit == 3 ? 'rd'
            : 'th';
    }

    private static BookingDetailsWrapper buildBookingDetails(Unit__c unit,Opportunity opportunity,List<Escrow_Account__c> escrowRecords,PaymentPlanWrapper paymentPlan,String currencyCode) {
        Date spaDate = opportunity != null ? opportunity.SPA_Signed_Date__c : null;
        Boolean hasScheduleAmount = paymentPlan.totalSummary != null && paymentPlan.totalSummary.totalAmount != null && !paymentPlan.milestones.isEmpty();
        Decimal purchaseAmount = hasScheduleAmount ? paymentPlan.totalSummary.totalAmount : (opportunity != null ? opportunity.Amount : null);

        String unitTypeLabel = unit.Unit_Type__c;
        for (Schema.PicklistEntry entry : Unit__c.Unit_Type__c.getDescribe().getPicklistValues()) {
            if (entry.getValue() == unit.Unit_Type__c) {
                unitTypeLabel = entry.getLabel();
                break;
            }
        }

        PurchasePriceWrapper purchasePrice = new PurchasePriceWrapper();
        purchasePrice.currencies  = currencyCode;
        purchasePrice.amount      = purchaseAmount != null ? purchaseAmount.setScale(2, RoundingMode.HALF_UP) : null;
        purchasePrice.formatted   = formatCurrency(purchaseAmount, currencyCode);
        purchasePrice.includesTax = hasScheduleAmount ? true : null;

        BookingDetailsWrapper bookingDetails = new BookingDetailsWrapper();
        bookingDetails.spaDate          = spaDate;
        bookingDetails.formattedSpaDate = formatDate(spaDate);
      //  bookingDetails.noOfCarParks     = unit.Default_Parking__c != null ? Integer.valueOf(unit.Default_Parking__c) : null;
        bookingDetails.propertyCategory = null;
        bookingDetails.purchasePrice    = purchasePrice;
        bookingDetails.towerBlock       = unit.Floor__r != null && unit.Floor__r.Block__r != null ? unit.Floor__r.Block__r.Name : null;
        bookingDetails.unitNumber       = unit.Unit_Name_Code__c;
        bookingDetails.unitType         = unitTypeLabel;
        bookingDetails.escrowAccountNo  = escrowRecords.isEmpty() ? null : escrowRecords[0].Name;
        bookingDetails.squareFeet       = unit.Salable_Area_sqft__c;
        return bookingDetails;
    }

    private static PaymentPlanWrapper buildPaymentPlan(List<Cost_Sheet_Payment_Schedule__c> scheduleRecords, String currencyCode) {
        List<PaymentMilestoneWrapper> milestones = new List<PaymentMilestoneWrapper>();
        Decimal totalAmount     = 0;
        Decimal totalPercentage = 0;

        for (Cost_Sheet_Payment_Schedule__c scheduleRecord : scheduleRecords) {
            Date trancheDate = scheduleRecord.Due_Date__c != null ? scheduleRecord.Due_Date__c : scheduleRecord.Pay_Date__c;
            Decimal milestoneAmount = scheduleRecord.Total_Amount_Inclusive_Of_Tax__c;

            PaymentMilestoneWrapper milestoneItem = new PaymentMilestoneWrapper();
            milestoneItem.id                   = String.isNotBlank(scheduleRecord.Name) ? scheduleRecord.Name : String.valueOf(scheduleRecord.Id);
            milestoneItem.description          = scheduleRecord.Description__c;
            milestoneItem.percentage           = scheduleRecord.Installment__c;
            milestoneItem.trancheDate          = trancheDate;
            milestoneItem.formattedTrancheDate = formatDate(trancheDate);
            milestoneItem.amount               = milestoneAmount != null ? milestoneAmount.setScale(2, RoundingMode.HALF_UP) : null;
            milestoneItem.formattedAmount      = formatCurrency(milestoneAmount, currencyCode);
            milestones.add(milestoneItem);

            totalAmount     += milestoneAmount != null ? milestoneAmount : 0;
            totalPercentage += scheduleRecord.Installment__c != null ? scheduleRecord.Installment__c : 0;
        }

        PaymentPlanSummaryWrapper totalSummary = new PaymentPlanSummaryWrapper();
        totalSummary.description          = 'Total (Inclusive of taxes)';
        totalSummary.totalPercentage      = milestones.isEmpty() ? null : totalPercentage.stripTrailingZeros().toPlainString() + '%';
        totalSummary.totalAmount          = milestones.isEmpty() ? null : totalAmount.setScale(2, RoundingMode.HALF_UP);
        totalSummary.formattedTotalAmount = milestones.isEmpty() ? null : formatCurrency(totalAmount, currencyCode);

        PaymentPlanWrapper paymentPlan = new PaymentPlanWrapper();
        paymentPlan.currencies   = currencyCode;
        paymentPlan.milestones   = milestones;
        paymentPlan.totalSummary = totalSummary;
        return paymentPlan;
    }

    private static String formatDate(Date dateValue) {
        if (dateValue == null) {
            return null;
        }
        return String.valueOf(dateValue.day()).leftPad(2, '0') + '/'
            + String.valueOf(dateValue.month()).leftPad(2, '0') + '/'
            + String.valueOf(dateValue.year());
    }

    private static String formatCurrency(Decimal amount, String currencyCode) {
        if (amount == null) {
            return null;
        }
        String plainAmount = amount.setScale(2, RoundingMode.HALF_UP).toPlainString();
        Boolean isNegative = plainAmount.startsWith('-');
        String unsignedAmount = isNegative ? plainAmount.substring(1) : plainAmount;
        List<String> amountParts = unsignedAmount.split('\\.');
        String integerDigits = amountParts[0];
        String groupedDigits = '';
        for (Integer index = 0; index < integerDigits.length(); index++) {
            Integer remainingDigits = integerDigits.length() - index;
            groupedDigits += integerDigits.substring(index, index + 1);
            if (remainingDigits > 1 && Math.mod(remainingDigits - 1, 3) == 0) {
                groupedDigits += ',';
            }
        }
        String currencyPrefix = String.isNotBlank(currencyCode) ? currencyCode + ' ' : '';
        return currencyPrefix + (isNegative ? '-' : '') + groupedDigits + '.' + amountParts[1];
    }

    private static PropertyDetailsResponse createResponse(Boolean isSuccess, Integer httpStatusCode, String message, PropertyDetailsData data) {
        PropertyDetailsResponse apiResponse = new PropertyDetailsResponse();
        apiResponse.success    = isSuccess;
        apiResponse.statusCode = httpStatusCode;
        apiResponse.message    = message;
        apiResponse.data       = data;
        return apiResponse;
    }

    public class PropertyDetailsResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public PropertyDetailsData data;
    }

    public class PropertyDetailsData {
        public String unitId;
        public String propertyName;
        public String salesOrderNo;
        public List<ApplicantWrapper> applicants;
        public BookingDetailsWrapper bookingDetails;
        public PaymentPlanWrapper paymentPlan;
    }

    public class ApplicantWrapper {
        public String applicantId;
        public String applicantType;
        public String fullName;
        public Boolean isPrimary;
    }

    public class BookingDetailsWrapper {
        public Date spaDate;
        public String formattedSpaDate;
        public Integer noOfCarParks;
        public String propertyCategory;
        public PurchasePriceWrapper purchasePrice;
        public String towerBlock;
        public String unitNumber;
        public String unitType;
        public String escrowAccountNo;
        public Decimal squareFeet;
    }

    public class PurchasePriceWrapper {
        public String currencies;
        public Decimal amount;
        public String formatted;
        public Boolean includesTax;
    }

    public class PaymentPlanWrapper {
        public String currencies;
        public List<PaymentMilestoneWrapper> milestones;
        public PaymentPlanSummaryWrapper totalSummary;
    }

    public class PaymentMilestoneWrapper {
        public String id;
        public String description;
        public Decimal percentage;
        public Date trancheDate;
        public String formattedTrancheDate;
        public Decimal amount;
        public String formattedAmount;
    }

    public class PaymentPlanSummaryWrapper {
        public String description;
        public String totalPercentage;
        public Decimal totalAmount;
        public String formattedTotalAmount;
    }
}