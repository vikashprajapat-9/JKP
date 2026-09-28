import { LightningElement, track } from 'lwc';
import getProjects from '@salesforce/apex/LeadAssignmentAdminController.getProjects';
import getAssignmentGroups from '@salesforce/apex/LeadAssignmentAdminController.getAssignmentGroups';
import createAssignmentGroup from '@salesforce/apex/LeadAssignmentAdminController.createAssignmentGroup';
import createAssignmentGroupMember from '@salesforce/apex/LeadAssignmentAdminController.createAssignmentGroupMember';
import deleteAssignmentGroupMember from '@salesforce/apex/LeadAssignmentAdminController.deleteAssignmentGroupMember';
import deleteAssignmentGroup from '@salesforce/apex/LeadAssignmentAdminController.deleteAssignmentGroup';
import getLeadScoreConfigs from '@salesforce/apex/LeadAssignmentAdminController.getLeadScoreConfigs';
import saveLeadScoreConfigs from '@salesforce/apex/LeadAssignmentAdminController.saveLeadScoreConfigs';
import getPriorityConfigs from '@salesforce/apex/LeadAssignmentAdminController.getPriorityConfigs';
import savePriorityConfigs from '@salesforce/apex/LeadAssignmentAdminController.savePriorityConfigs';
import deletePriorityConfig from '@salesforce/apex/LeadAssignmentAdminController.deletePriorityConfig';
import getLeadPriorityOptions from '@salesforce/apex/LeadAssignmentAdminController.getLeadPriorityOptions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LeadAssignmentAdminPanel extends LightningElement {

    @track projectOptions = [];
    @track assignmentGroups = [];
    @track scoreConfigs = [];
    @track priorityConfigs = [];
    @track leadPriorityOptions = [];
    scorePageSize = 10;
    scoreCurrentPage = 1;

    selectedProjectId;
    selectedProjectName;
    generatedSoql = '';

    maxAssignmentCount = 200;
    casesToAssign = 1;
    isActive = true;

    showMemberModal = false;
    selectedGroupId;
    selectedUserId;

   selectedField = 'Designation__c';
   fieldTabs = [];

    memberAssignmentId;
    // memberMaxCasePerDay = 100;
    memberMaxAssignmentCount = 100;
    memberActive = true;

    connectedCallback() {
    this.loadProjects();
    this.loadGroups();
    this.loadScoreConfigs();
    this.loadPriorityConfigs();
    this.loadLeadPriorityOptions();
    }

    get paginatedScoreConfigs() {
        const start = (this.scoreCurrentPage - 1) * this.scorePageSize;
        const end = start + this.scorePageSize;
        return this.scoreConfigs.slice(start, end);
    }

    // get totalScorePages() {
    //     return Math.ceil(this.scoreConfigs.length / this.scorePageSize);
    // }
   get totalScorePages() {
        const total = this.scoreConfigs.filter( item => item.fieldApiName === this.selectedField  ).length;
        return Math.ceil(total / this.scorePageSize) || 1;
    }

    get isFirstScorePage() {
        return this.scoreCurrentPage === 1;
    }

    get isLastScorePage() {
        return this.scoreCurrentPage >= this.totalScorePages;
    }

    get scorePageInfo() {
        return 'Page ' + this.scoreCurrentPage + ' of ' + this.totalScorePages;
    }

    get filteredPaginatedScoreConfigs() {
        const filtered = this.scoreConfigs.filter(  item => item.fieldApiName === this.selectedField );
        const start = (this.scoreCurrentPage - 1) * this.scorePageSize;
        return filtered.slice(start, start + this.scorePageSize);
    }

    handlePreviousScorePage() {
        if (this.scoreCurrentPage > 1) {
            this.scoreCurrentPage--;
        }
    }

    handleNextScorePage() {
        if (this.scoreCurrentPage < this.totalScorePages) {
            this.scoreCurrentPage++;
        }
    }
 
    prepareTabs() {
        const map = {};
        this.scoreConfigs.forEach(item => {
            if (!map[item.fieldApiName]) {
                map[item.fieldApiName] = { apiName: item.fieldApiName,  label: item.fieldLabel, count: 0  };
            }
            map[item.fieldApiName].count++;
        });
        this.fieldTabs = Object.values(map).map(tab => {
            return {  ...tab,  cssClass: tab.apiName === this.selectedField ? 'field-tab active'  : 'field-tab'  };
        });

    }
    loadProjects() {
        getProjects()
            .then(result => {
                console.log('Projects', JSON.stringify(result));
                this.projectOptions = result.map(item => {
                    return {
                        label: item.Name,
                        value: item.Id
                    };
                });
            })
            .catch(error => {
                console.error('Projects Error', error);
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }

    loadGroups() {
        getAssignmentGroups()
            .then(result => {
                console.log('Assignment Groups:', JSON.parse(JSON.stringify(result)));
                this.assignmentGroups = result;
            })
            .catch(error => {
                console.error(error);
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }

    handleProjectChange(event) {
        this.selectedProjectId = event.detail.value;

        const selected = this.projectOptions.find(
            item => item.value === this.selectedProjectId
        );

        this.selectedProjectName = selected ? selected.label : '';

       // this.generatedSoql =
    // "SELECT Id, Project__c, Project__r.Name, Is_User_Assigned__c, OwnerId, Status " +
    // "FROM Lead WHERE Is_User_Assigned__c = false " +
    // "AND Project__r.Name = '" + this.selectedProjectName + "'";
    }

    handleMaxAssignmentChange(event) {
        this.maxAssignmentCount = event.target.value;
    }

    handleCasesChange(event) {
        this.casesToAssign = event.target.value;
    }

    handleActiveChange(event) {
        this.isActive = event.target.checked;
    }

    createGroup() {
        createAssignmentGroup({
            projectId: this.selectedProjectId,
            projectName: this.selectedProjectName,
            maxAssignmentCount: this.maxAssignmentCount,
            casesToAssign: this.casesToAssign,
            isActive: this.isActive
        })
            .then(() => {
                this.showToast('Success', 'Assignment Group created successfully.', 'success');
                this.resetGroupForm();
                this.loadGroups();
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }
   handleFieldTabClick(event) {
        this.selectedField = event.currentTarget.dataset.field;
        this.scoreCurrentPage = 1;
        this.prepareTabs();
    }
    resetGroupForm() {
        this.selectedProjectId = null;
        this.selectedProjectName = null;
        this.generatedSoql = '';
        this.maxAssignmentCount = 200;
        this.casesToAssign = 1;
        this.isActive = true;
    }

    openMemberModal(event) {
        this.selectedGroupId = event.currentTarget.dataset.id;
        this.showMemberModal = true;
    }

    closeMemberModal() {
        this.showMemberModal = false;
        this.resetMemberForm();
    }

    handleUserChange(event) {
        this.selectedUserId = event.detail.recordId;
    }

    handleMemberAssignmentId(event) {
        this.memberAssignmentId = event.target.value;
    }

    /* handleMemberMaxCase(event) {
        this.memberMaxCasePerDay = event.target.value;
    } */

    handleMemberMaxAssignment(event) {
        this.memberMaxAssignmentCount = event.target.value;
    }

    handleMemberActive(event) {
        this.memberActive = event.target.checked;
    }

    saveMember() {
        createAssignmentGroupMember({
            assignmentGroupId: this.selectedGroupId,
            userId: this.selectedUserId,
            assignmentId: this.memberAssignmentId,
            // maxCasePerDay: this.memberMaxCasePerDay,
            maxAssignmentCount: this.memberMaxAssignmentCount,
            active: this.memberActive
        })
            .then(() => {
                this.showToast('Success', 'Member added successfully.', 'success');
                this.closeMemberModal();
                this.loadGroups();
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }

    deleteMember(event) {
        const memberId = event.currentTarget.dataset.id;

        deleteAssignmentGroupMember({ memberId })
            .then(() => {
                this.showToast('Success', 'Member removed successfully.', 'success');
                this.loadGroups();
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }

    deleteGroup(event) {
        const groupId = event.currentTarget.dataset.id;

        deleteAssignmentGroup({ groupId })
            .then(() => {
                this.showToast('Success', 'Assignment Group deleted successfully.', 'success');
                this.loadGroups();
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    }

    resetMemberForm() {
        this.selectedGroupId = null;
        this.selectedUserId = null;
        this.memberAssignmentId = null;
        // this.memberMaxCasePerDay = 100;
        this.memberMaxAssignmentCount = 100;
        this.memberActive = true;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    getErrorMessage(error) {
    if (error && error.body) {
        if (error.body.message) {
            return error.body.message;
        }

        if (error.body.pageErrors && error.body.pageErrors.length > 0) {
            return error.body.pageErrors[0].message;
        }

        if (error.body.fieldErrors) {
            const fields = Object.keys(error.body.fieldErrors);
            if (fields.length > 0) {
                return error.body.fieldErrors[fields[0]][0].message;
            }
        }
    }

    return 'Something went wrong.';
}

    loadScoreConfigs() {
    getLeadScoreConfigs()
        .then(result => {
            console.log('Score Configs', JSON.stringify(result));
            this.scoreConfigs = result.map((item, index) => {
                return {
                    ...item,
                    uniqueKey: item.fieldApiName + '-' + item.picklistValue + '-' + index,
                    originalIndex: index,
                    serialNumber: index + 1
                };
            });

            this.scoreCurrentPage = 1;
            this.prepareTabs();
        })
        .catch(error => {
             console.error('Score Error', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        });
}

handleScoreChange(event) {
    const index = event.target.dataset.index;
    this.scoreConfigs[index].score = event.target.value;
}

handleScoreActiveChange(event) {
    const index = event.target.dataset.index;
    this.scoreConfigs[index].active = event.target.checked;
}

saveScoreConfig() {
    const configsToSave = this.scoreConfigs
        .filter(item => Number(item.score) > 0)
        .map(item => {
            return {
                recordId: item.recordId,
                fieldApiName: item.fieldApiName,
                fieldLabel: item.fieldLabel,
                picklistValue: item.picklistValue,
                score: Number(item.score),
                active: item.active
            };
        });

    if (configsToSave.length === 0) {
        this.showToast('Warning', 'Please enter score greater than 0 for at least one value.', 'warning');
        return;
    }

    saveLeadScoreConfigs({ configList: configsToSave })
        .then(result => {
            this.showToast('Success', result, 'success');
            this.loadScoreConfigs();
        })
        .catch(error => {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        });
}

loadPriorityConfigs() {
    getPriorityConfigs()
        .then(result => {
            console.log('Priority Configs', JSON.stringify(result));
            this.priorityConfigs = result.map((item, index) => {
                return {
                    ...item,
                    tempKey: item.Id ? item.Id : 'temp-' + index
                };
            });
        })
        .catch(error => {
            console.error('Priority Error', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        });
}

loadLeadPriorityOptions() {
    getLeadPriorityOptions()
        .then(result => {
            console.log('Priority Options', JSON.stringify(result));
            this.leadPriorityOptions = result;
        })
        .catch(error => {
            console.error('Priority Options Error', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        });
}

addPriorityRow() {
    this.priorityConfigs = [
        ...this.priorityConfigs,
        {
            tempKey: 'temp-' + Date.now(),
            Min_Score__c: 0,
            Max_Score__c: 0,
            Priority__c: '',
            Active__c: true
        }
    ];
}

handlePriorityChange(event) {
    const index = event.target.dataset.index;
    const field = event.target.dataset.field;

    this.priorityConfigs[index][field] = event.target.value;
}

handlePriorityActiveChange(event) {
    const index = event.target.dataset.index;
    this.priorityConfigs[index].Active__c = event.target.checked;
}

savePriorityConfig() {
    if (!this.priorityConfigs || this.priorityConfigs.length === 0) {
        this.showToast('Warning', 'No priority matrix records to save.', 'warning');
        return;
    }

    const hasEmptyPriority = this.priorityConfigs.some(item => !item.Priority__c);
    if (hasEmptyPriority) {
        this.showToast('Warning', 'Please select a priority for all rows before saving.', 'warning');
        return;
    }

    const priorities = this.priorityConfigs.map(item => item.Priority__c);
    const uniquePriorities = new Set(priorities);
    if (priorities.length !== uniquePriorities.size) {
        this.showToast('Warning', 'Each priority can only be assigned to one row. Please remove duplicates.', 'warning');
        return;
    }

    savePriorityConfigs({
        priorityList: this.priorityConfigs
    })
        .then(() => {
            this.showToast('Success', 'Priority matrix saved successfully.', 'success');
            this.loadPriorityConfigs();
        })
        .catch(error => {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        });
}

removePriorityRow(event) {
    const recordId = event.currentTarget.dataset.id;
    const index = event.currentTarget.dataset.index;

    if (recordId) {
        deletePriorityConfig({ recordId })
            .then(() => {
                this.showToast('Success', 'Priority row deleted successfully.', 'success');
                this.loadPriorityConfigs();
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            });
    } else {
        this.priorityConfigs.splice(index, 1);
        this.priorityConfigs = [...this.priorityConfigs];
    }
}
}