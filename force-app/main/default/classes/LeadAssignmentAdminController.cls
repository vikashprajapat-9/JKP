public with sharing class LeadAssignmentAdminController {

    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjects() {
        return [
            SELECT Id, Name
            FROM Project__c
            ORDER BY Name
        ];
    }

    @AuraEnabled
    public static List<AssignmentGroupWrapper> getAssignmentGroups() {
        List<Assignment_Group__c> groups = [
            SELECT Id, Name, Project__c, Project__r.Name, Execution_SOQL__c,
                   Round_Robin_Queue_Name__c, Supported_Sobject__c,
                   Max_Sobject_Assignment_Count__c, Type__c, IsActive__c,Total_Members__c
                   //Case_to_Assign_in_Single_Transaction__c
            FROM Assignment_Group__c
            WHERE Supported_Sobject__c = 'Lead'
            ORDER BY CreatedDate DESC
        ];

        Set<Id> groupIds = new Set<Id>();
        for (Assignment_Group__c grp : groups) {
            groupIds.add(grp.Id);
        }

        Map<Id, List<Assignment_Group_Member__c>> memberMap = new Map<Id, List<Assignment_Group_Member__c>>();

        if (!groupIds.isEmpty()) {
            for (Assignment_Group_Member__c mem : [
                SELECT Id, Name, Assignment_Group__c, Group_Member__c,
                       Group_Member__r.Name, Assignment_Id__c,
                       /* Max_Case_Per_Day__c, */ Max_Sobject_Assignment_Count__c,
                       Active__c,  Out_Of_Office__c //BreakTime_Started__c,
                FROM Assignment_Group_Member__c
                WHERE Assignment_Group__c IN :groupIds
                ORDER BY Assignment_Id__c ASC
            ]) {
                if (!memberMap.containsKey(mem.Assignment_Group__c)) {
                    memberMap.put(mem.Assignment_Group__c, new List<Assignment_Group_Member__c>());
                }
                memberMap.get(mem.Assignment_Group__c).add(mem);
            }
        }

        List<AssignmentGroupWrapper> response = new List<AssignmentGroupWrapper>();

        for (Assignment_Group__c grp : groups) {
            AssignmentGroupWrapper wrap = new AssignmentGroupWrapper();
            wrap.groupRecord = grp;
            wrap.members = memberMap.containsKey(grp.Id)
                ? memberMap.get(grp.Id)
                : new List<Assignment_Group_Member__c>();
                wrap.projectName = grp.Project__r != null ? grp.Project__r.Name : '';
                wrap.totalMembers = wrap.members.size();

            response.add(wrap);
        }

        return response;
    }

    @AuraEnabled
public static Id createAssignmentGroup(
    Id projectId,
    String projectName,
    Integer maxAssignmentCount,
    Integer casesToAssign,
    Boolean isActive
) {
    if (projectId == null) {
        throw new AuraHandledException('Project is required.');
    }

    Integer existingGroupCount = [
        SELECT COUNT()
        FROM Assignment_Group__c
        WHERE Project__c = :projectId
        AND Supported_Sobject__c = 'Lead'
    ];

    if (existingGroupCount > 0) {
        throw new AuraHandledException('Assignment Group already exists for this Project.');
    }

    String query =
        'SELECT Id, Project__c, Project__r.Name, Is_User_Assigned__c, OwnerId, Status ' +
        'FROM Lead ' +
        'WHERE Is_User_Assigned__c = false ' +
        'AND Project__r.Name = \'' + String.escapeSingleQuotes(projectName) + '\'';

    Assignment_Group__c grp = new Assignment_Group__c();
    grp.Name = 'Project - ' + projectName + ' (Pre Sales)';
    grp.Project__c = projectId;
    grp.Execution_SOQL__c = query;
    grp.Round_Robin_Queue_Name__c = 'Lead Assignment Queue';
    grp.Supported_Sobject__c = 'Lead';
    grp.Type__c = 'Pre Sales';
    grp.Max_Sobject_Assignment_Count__c = maxAssignmentCount;
   // grp.Case_to_Assign_in_Single_Transaction__c = casesToAssign;
    grp.isActive__c = isActive;

    insert grp;
    return grp.Id;
}

    @AuraEnabled
public static Id createAssignmentGroupMember(
    Id assignmentGroupId,
    Id userId,
    Integer assignmentId,
    /* Integer maxCasePerDay, */
    Integer maxAssignmentCount,
    Boolean active
) {
    if (assignmentGroupId == null) {
        throw new AuraHandledException('Assignment Group is required.');
    }

    if (userId == null) {
        throw new AuraHandledException('Group Member/User is required.');
    }

    Integer existingMemberCount = [
        SELECT COUNT()
        FROM Assignment_Group_Member__c
        WHERE Assignment_Group__c = :assignmentGroupId
        AND Group_Member__c = :userId
    ];

    if (existingMemberCount > 0) {
        throw new AuraHandledException('This member is already added in the selected Assignment Group.');
    }

    Assignment_Group_Member__c mem = new Assignment_Group_Member__c();
    mem.Assignment_Group__c = assignmentGroupId;
    mem.Group_Member__c = userId;
    mem.Assignment_Id__c = assignmentId;
    // mem.Max_Case_Per_Day__c = maxCasePerDay;
    mem.Max_Sobject_Assignment_Count__c = maxAssignmentCount;
    mem.Active__c = active;

    insert mem;
    return mem.Id;
}

    @AuraEnabled
    public static void deleteAssignmentGroupMember(Id memberId) {
        Assignment_Group_Member__c mem = [
            SELECT Id, Assignment_Group__c
            FROM Assignment_Group_Member__c
            WHERE Id = :memberId
            LIMIT 1
        ];

        Id groupId = mem.Assignment_Group__c;
        delete mem;

        updateTotalMembers(groupId);
    }

    @AuraEnabled
    public static void deleteAssignmentGroup(Id groupId) {
        if (groupId == null) {
            throw new AuraHandledException('Assignment Group Id is required.');
        }

        delete [
            SELECT Id
            FROM Assignment_Group_Member__c
            WHERE Assignment_Group__c = :groupId
        ];

        delete [
            SELECT Id
            FROM Assignment_Group__c
            WHERE Id = :groupId
            LIMIT 1
        ];
    }

    private static void updateTotalMembers(Id groupId) {
        Integer totalMembers = [
            SELECT COUNT()
            FROM Assignment_Group_Member__c
            WHERE Assignment_Group__c = :groupId
        ];

        Assignment_Group__c grp = new Assignment_Group__c(
            Id = groupId
            //Total_Members__c = totalMembers
        );

        update grp;
    }

    public class AssignmentGroupWrapper {
        @AuraEnabled public Assignment_Group__c groupRecord;
        @AuraEnabled public List<Assignment_Group_Member__c> members;
        @AuraEnabled public String projectName;
        @AuraEnabled public Integer totalMembers;
    }

	@AuraEnabled
public static List<LeadScoreConfigWrapper> getLeadScoreConfigs() {

    Map<String, String> fieldLabelMap = new Map<String, String>{
        'Designation__c' => 'Designation',
        'Purchase_Type__c' => 'Purchase Type',
        'Budget_Alignment__c' => 'Budget Alignment',
        'Time_to_Purchase__c' => 'Time to Purchase'
    };

    Map<String, List<String>> fieldValueMap = new Map<String, List<String>>{
        'Designation__c' => new List<String>{
            'Salaried Employee','Senior Professional','Manager','IT Professional',
            'Government Employee','Business Owner','Self Employed','Entrepreneur','Doctor',
            'CA / Lawyer','NRI','Retired','Homemaker','Freelancer','Other'
        },
        'Purchase_Type__c' => new List<String>{
            'Investment','Residential (Self Use)','Second Home','Rental Income',
            'Commercial Investment','Plot Purchase','Villa Purchase','Apartment Purchase','Other'
        },
        'Budget_Alignment__c' => new List<String>{
            'Below Project Budget','Matching Budget','Slightly Above Budget','Premium Buyer',
            'Luxury Buyer','Budget Not Finalized','Financial Assistance Required'
        },
        'Time_to_Purchase__c' => new List<String>{
            'Immediate','Within 1 Month','Within 3 Months','Within 6 Months',
            'Within 1 Year','Just Exploring','Future Investment','Not Decided Yet'
        }
    };

    Map<String, Lead_Score_Config__c> existingMap = new Map<String, Lead_Score_Config__c>();

    for (Lead_Score_Config__c cfg : [
        SELECT Id, Field_API_Name__c, Field_Label__c, Picklist_Value__c, Score__c, Active__c
        FROM Lead_Score_Config__c
    ]) {
        existingMap.put(cfg.Field_API_Name__c + '###' + cfg.Picklist_Value__c, cfg);
    }

    List<LeadScoreConfigWrapper> response = new List<LeadScoreConfigWrapper>();

    for (String fieldApi : fieldValueMap.keySet()) {
        for (String value : fieldValueMap.get(fieldApi)) {

            String key = fieldApi + '###' + value;

            LeadScoreConfigWrapper wrap = new LeadScoreConfigWrapper();
            wrap.fieldApiName = fieldApi;
            wrap.fieldLabel = fieldLabelMap.get(fieldApi);
            wrap.picklistValue = value;
            wrap.score = 0;
            wrap.active = true;

            if (existingMap.containsKey(key)) {
                Lead_Score_Config__c cfg = existingMap.get(key);
                wrap.recordId = cfg.Id;
                wrap.score = cfg.Score__c;
                wrap.active = cfg.Active__c;
            }

            response.add(wrap);
        }
    }

    return response;
}

@AuraEnabled
public static String saveLeadScoreConfigs(List<LeadScoreConfigWrapper> configList) {
	system.debug('configList '+configList);

    if (configList == null || configList.isEmpty()) {
        throw new AuraHandledException('No score configuration received from UI.');
    }

    Set<String> keys = new Set<String>();

    for (LeadScoreConfigWrapper wrap : configList) {
        if (
            String.isNotBlank(wrap.fieldApiName) &&
            String.isNotBlank(wrap.picklistValue) &&
            wrap.score != null &&
            wrap.score > 0
        ) {
            keys.add(wrap.fieldApiName + '###' + wrap.picklistValue);
        }
    }

    if (keys.isEmpty()) {
        throw new AuraHandledException('No valid score configuration found. Please enter score greater than 0.');
    }

    Map<String, Lead_Score_Config__c> existingMap = new Map<String, Lead_Score_Config__c>();

    for (Lead_Score_Config__c existing : [
        SELECT Id, Field_API_Name__c, Picklist_Value__c
        FROM Lead_Score_Config__c
        WHERE Field_API_Name__c != null
        AND Picklist_Value__c != null
    ]) {
        String key = existing.Field_API_Name__c + '###' + existing.Picklist_Value__c;

        if (keys.contains(key)) {
            existingMap.put(key, existing);
        }
    }

    List<Lead_Score_Config__c> recordsToUpsert = new List<Lead_Score_Config__c>();

    for (LeadScoreConfigWrapper wrap : configList) {

        if (
            String.isBlank(wrap.fieldApiName) ||
            String.isBlank(wrap.picklistValue) ||
            wrap.score == null ||
            wrap.score <= 0
        ) {
            continue;
        }

        String key = wrap.fieldApiName + '###' + wrap.picklistValue;

        Lead_Score_Config__c cfg = new Lead_Score_Config__c();

        if (existingMap.containsKey(key)) {
            cfg.Id = existingMap.get(key).Id;
        }

        cfg.Field_API_Name__c = wrap.fieldApiName;
        cfg.Field_Label__c = wrap.fieldLabel;
        cfg.Picklist_Value__c = wrap.picklistValue;
        cfg.Score__c = wrap.score;
        cfg.Active__c = wrap.active == null ? true : wrap.active;

        recordsToUpsert.add(cfg);
    }

    if (recordsToUpsert.isEmpty()) {
        throw new AuraHandledException('No records prepared for save. Please check score values.');
    }
	system.debug('recordsToUpsert ==> '+recordsToUpsert);

    upsert recordsToUpsert;

    return recordsToUpsert.size() + ' Lead Score Config record(s) saved successfully.';
}

@AuraEnabled
public static List<Lead_Priority_Configs__c> getPriorityConfigs() {
    return [
        SELECT Id, Name, Min_Score__c, Max_Score__c, Priority__c, Active__c
        FROM Lead_Priority_Configs__c
        ORDER BY Min_Score__c ASC
    ];
}

@AuraEnabled
public static void savePriorityConfigs(List<Lead_Priority_Configs__c> priorityList) {
    if (priorityList == null || priorityList.isEmpty()) {
        return;
    }

    for (Lead_Priority_Configs__c cfg : priorityList) {
        cfg.Name = cfg.Priority__c + ' - ' + cfg.Min_Score__c + ' to ' + cfg.Max_Score__c;
    }

    upsert priorityList;
}

@AuraEnabled
public static void deletePriorityConfig(Id recordId) {
    delete [
        SELECT Id
        FROM Lead_Priority_Configs__c
        WHERE Id = :recordId
        LIMIT 1
    ];
}

@AuraEnabled(cacheable=true)
public static List<Map<String, String>> getLeadPriorityOptions() {
    List<Map<String, String>> options = new List<Map<String, String>>();
    Schema.DescribeFieldResult fieldResult = Lead.Lead_Priority__c.getDescribe();
    List<Schema.PicklistEntry> ple = fieldResult.getPicklistValues();
    for (Schema.PicklistEntry pickListVal : ple) {
        Map<String, String> option = new Map<String, String>();
        option.put('label', pickListVal.getLabel());
        option.put('value', pickListVal.getValue());
        options.add(option);
    }
    return options;
}

public class LeadScoreConfigWrapper {
    @AuraEnabled public Id recordId { get; set; }
    @AuraEnabled public String fieldApiName { get; set; }
    @AuraEnabled public String fieldLabel { get; set; }
    @AuraEnabled public String picklistValue { get; set; }
    @AuraEnabled public Decimal score { get; set; }
    @AuraEnabled public Boolean active { get; set; }
}
}