@RestResource(urlMapping='/api/v1/create-website-lead')
global without sharing class API_CreateWebsiteLead {

    private static final String LEAD_SOURCE = 'Digital';
    private static final String LEAD_SUB_SOURCE = 'Website Forms';
    private static final Pattern EMAIL_PATTERN =Pattern.compile('^[\\w.+-]+@[\\w-]+\\.[a-zA-Z]{2,}$');

    @HttpPost
    global static void createWebsiteLead() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');
        try {
            WebsiteLeadResponse result = createLead(request);
            response.statusCode = result.statusCode;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            System.debug('API_CreateWebsiteLead error: ' +e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_CreateWebsiteLead','createWebsiteLead',e, null,'WEB - SFDC');
            response.statusCode = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(buildResponse(false,500,'An unexpected error occurred while creating the Lead.', null )));
        }
    }

    private static WebsiteLeadResponse createLead(RestRequest request) {
        WebsiteLeadRequest input;
        try {
            if (request.requestBody == null || String.isBlank(request.requestBody.toString())) {
                return buildResponse(false, 400, 'Request body is required.', null );
            }
            input = (WebsiteLeadRequest) JSON.deserialize(request.requestBody.toString(), WebsiteLeadRequest.class);
        } catch (Exception e) {
            return buildResponse(false, 400, 'Invalid request body.', null );
        }
        if (input == null) {
            return buildResponse( false, 400, 'Request body is required.', null);
        }

        // 1.  name
        if (String.isBlank(input.fullName)) {
            return buildResponse(false, 400, 'fullName is required.', null );
        }
        String fullName = input.fullName.trim();
        if (fullName.length() <= 2) {
            return buildResponse(false, 400, 'Please enter a valid Lead Name.', null);
        }

        // 2. Validate phone
        if (String.isBlank(input.phone)) {
            return buildResponse(false, 400, 'Phone is required.', null);
        }

        String phone = input.phone.trim();
        String countryCode = input.countryCode == null ? '' : input.countryCode.trim();
        String fullPhone = countryCode + phone;
        // 3. Validate email 
        String email;
        if (String.isNotBlank(input.email)) {
            email = input.email.trim();
            if (!EMAIL_PATTERN.matcher(email).matches()) {
                return buildResponse(false, 400, 'Please provide a valid email.', null);
            }
        }

        // 4. Validate project 
        if (String.isBlank(input.projectId)) {
            return buildResponse( false, 400, 'projectId is required.', null );
        }
        String projectIdText = input.projectId.trim();
        if (!isValidSalesforceId(projectIdText)) {
            return buildResponse(false, 400, 'projectId must be a valid Salesforce ID.', null);
        }

        Id projectId = Id.valueOf(projectIdText);

        List<Project__c> matchedProjects = [ SELECT Id, Name FROM Project__c WHERE Id = :projectId AND Active__c = true LIMIT 1 ];
        if (matchedProjects.isEmpty()) {
            return buildResponse(false, 404, 'Project not found.', null);
        }
        Project__c project = matchedProjects[0];
        // 6. Set Company:
        String company;
        if (String.isNotBlank(input.company)) {
            company = input.company.trim();
        } else {
            company = fullName + ' - ' + project.Name;
        }
        // Company
        if (company.length() > 255) {
            return buildResponse(false,400,'Company cannot exceed 255 characters.', null );
        }

        // 7. Create Lead
        Lead newLead = new Lead();
        newLead.LastName = fullName;
        newLead.Company = company;
        newLead.Phone = fullPhone;
        newLead.Project__c = project.Id;
        if (String.isNotBlank(email)) {
            newLead.Email = email;
        }
        newLead.LeadSource = LEAD_SOURCE;
        newLead.Lead_Sub_Source__c = LEAD_SUB_SOURCE;
        try {
            Database.insert(newLead, AccessLevel.SYSTEM_MODE);
        } catch (DmlException dmlEx) {
            System.debug('Lead insertion failed: ' + dmlEx.getMessage() );
            IntegrationLogUtility.captureError('API_CreateWebsiteLead','createLead',dmlEx,null,'WEB - SFDC' );
            return buildResponse(false,400,dmlEx.getDmlMessage(0),null);
        }
        Lead insertedLead = [SELECT Id, Name, Company, Email, Phone,Status, LeadSource, Lead_Sub_Source__c,Project__c, CreatedDate FROM Lead WHERE Id = :newLead.Id WITH SYSTEM_MODE LIMIT 1];
        WebsiteLeadData data = new WebsiteLeadData();
        data.leadId = String.valueOf(insertedLead.Id);
        data.leadName = insertedLead.Name;
        data.company = insertedLead.Company;
        data.email = insertedLead.Email;
        data.phone = insertedLead.Phone;
        data.projectId = String.valueOf(project.Id);
        data.projectName = project.Name;
        data.leadSource = insertedLead.LeadSource;
        data.leadSubSource = insertedLead.Lead_Sub_Source__c;
        data.status = insertedLead.Status;
        return buildResponse(true,201,'Website Lead created successfully.', data);
    }

    private static Boolean isValidSalesforceId(String recordId) {
        try {
            Id.valueOf(recordId);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static WebsiteLeadResponse buildResponse(Boolean success,Integer statusCode, String message, WebsiteLeadData data) {
        WebsiteLeadResponse result = new WebsiteLeadResponse();
        result.success = success;
        result.statusCode = statusCode;
        result.message = message;
        result.data = data;
        return result;
    }
    global class WebsiteLeadRequest {
        public String fullName;
        public String phone;
        public String countryCode;
        public String email;
        public String projectId;
        public String company;
    }
    global class WebsiteLeadResponse {
        public Boolean success;
        public Integer statusCode;
        public String message;
        public WebsiteLeadData data;
    }

    global class WebsiteLeadData {
        public String leadId;
        public String leadName;
        public String company;
        public String email;
        public String phone;
        public String projectId;
        public String projectName;
        public String leadSource;
        public String leadSubSource;
        public String status;
    }
}