public class SobjectLoadAssignmentUtility {
    
    
    Public static  Map<String,Id> GetQueuesNameAndId(){
        List<Assignment_Group__c> grouplist = [Select id , Round_Robin_Queue_Name__c From Assignment_Group__c where Type__c ='Pre Sales'];
        system.debug('grouplist::>>' + grouplist);
        set<string> queueName = new  set<string>();
        Map<String,Id> mapofQueuenameAndId = new Map<String,Id>();
        for(Assignment_Group__c assignGroupRec : grouplist){
            if (assignGroupRec.Round_Robin_Queue_Name__c != null) {
                queueName.add(assignGroupRec.Round_Robin_Queue_Name__c);
            }
            
            list<Group> queueList = [Select id,Name From Group WHERE Type = 'Queue' AND Name IN:queueName];
            system.debug('queueList::>>' + queueList);
            for(Group queueRec :queueList ){
                mapofQueuenameAndId.put(queueRec.Name, queueRec.Id);
            }
        }
        return mapofQueuenameAndId;
    }
    
    Public static  Map<id,Assignment_Group__c> GetassigmentGroup(){
        Map<id,Assignment_Group__c> mapofIdandAssingmentGroup = new Map<id,Assignment_Group__c>();
        // list<Assignment_Group__c> assigmentgroupList = [SELECT Case_Stage__c,Case_to_Assign_in_Single_Transaction__c,CreatedDate,Execution_SOQL__c,Id,isActive__c,Last_Allocated_RRid__c,Max_Sobject_Assignment_Count__c,Name,OwnerId,Round_Robin_Queue_Name__c FROM Assignment_Group__c Where isActive__c = True AND Type__c = 'Pre Sales'];
        list<Assignment_Group__c> assigmentgroupList = [SELECT CreatedDate,Execution_SOQL__c,Id,isActive__c,Last_Allocated_RRid__c,Max_Sobject_Assignment_Count__c,Name,OwnerId,Round_Robin_Queue_Name__c FROM Assignment_Group__c Where isActive__c = True AND Type__c = 'Pre Sales'];
        
        system.debug('assigmentgroupList::>>' + assigmentgroupList);
        if(!assigmentgroupList.IsEmpty()){
            for(Assignment_Group__c assignGroup : assigmentgroupList){
                System.debug('entere the condition if assigngroup');
                if (assignGroup.id != null) {
                    mapofIdandAssingmentGroup.put(assignGroup.id, assignGroup);
                }
            }
        }
        return mapofIdandAssingmentGroup;
    }
    
    public static Map<Id, Integer> getCaseCount(String GroupId) {
        system.debug('groupId::>>' + GroupId);
        List<Assignment_Group_Member__c> assignmentGroupMemberRecords = [SELECT Id, Max_Sobject_Assignment_Count__c, Assignment_Group__r.Supported_Sobject__c,Active__c FROM Assignment_Group_Member__c WHERE Assignment_Group__c = :GroupId];
        system.debug('assignmentGroupMemberRecords::>>' + assignmentGroupMemberRecords);
        Set<Id> rv_groupMember = new Set<Id>();
        for (Assignment_Group_Member__c assgn : assignmentGroupMemberRecords) {
            rv_groupMember.add(assgn.Id);
        }
        String supportedSObject;
        if(!assignmentGroupMemberRecords.isEmpty()){
            supportedSObject = assignmentGroupMemberRecords[0].Assignment_Group__r.Supported_Sobject__c;  
            String soqlQuery = 'SELECT Id, CreatedDate, AGM_Related_to__c ' +
                'FROM ' + supportedSObject + ' ' +
                'WHERE AGM_Related_to__c IN :rv_groupMember ' +
                'AND CreatedDate = TODAY';
                system.debug('soqlQuery::>>' + soqlQuery);
                system.debug('supportedSObject::>>' + supportedSObject);
            List<SObject> caseRecords = Database.query(soqlQuery);
            Map<Id, Integer> caseCountMap = new Map<Id, Integer>();
            for (SObject caseRecord : caseRecords) {
                Id agmRelatedToId = (Id) caseRecord.get('AGM_Related_to__c');
                if (caseCountMap.containsKey(agmRelatedToId)) {
                    caseCountMap.put(agmRelatedToId, caseCountMap.get(agmRelatedToId) + 1);
                } else {
                    caseCountMap.put(agmRelatedToId, 1);
                }
            }
            return caseCountMap;
        }else {
            return new Map<Id, Integer>();
        }  
    }
    
    public static Map<Id, List<Assignment_Group_Member__c>> assignmentGroupMembers() {
        Map<Id, List<Assignment_Group_Member__c>> mapOfIdAndAssignmentGroup = new Map<Id, List<Assignment_Group_Member__c>>();
        List<Assignment_Group_Member__c> assignmentGroupList = [SELECT Id, Assignment_Group__r.Id, Active__c FROM Assignment_Group_Member__c WHERE Active__c = true ORDER BY Assignment_Id__c];
        system.debug('assignmentGroupList::>>' + assignmentGroupList);
        
        if (!assignmentGroupList.isEmpty()) {
            for (Assignment_Group_Member__c assignGroupMem : assignmentGroupList) {
                Id groupId = assignGroupMem.Assignment_Group__r.Id;
                if (groupId != null) {
                    if (!mapOfIdAndAssignmentGroup.containsKey(groupId)) {
                        mapOfIdAndAssignmentGroup.put(groupId, new List<Assignment_Group_Member__c>());
                    }
                    mapOfIdAndAssignmentGroup.get(groupId).add(assignGroupMem);
                }
            }
        }
        return mapOfIdAndAssignmentGroup;
    }
}