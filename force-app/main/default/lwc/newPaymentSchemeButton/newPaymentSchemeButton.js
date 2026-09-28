import { LightningElement, track,wire,api} from 'lwc';
import getAllCompanies from '@salesforce/apex/paymentSchemeNewButtonController.getAllCompanies';
import getProjects from '@salesforce/apex/paymentSchemeNewButtonController.getProjects';
import getBlocks from '@salesforce/apex/paymentSchemeNewButtonController.getBlocks';
import getPaymentScheduleOptions from '@salesforce/apex/paymentSchemeNewButtonController.getPaymentScheduleOptions';
import insertPaymentScheme from '@salesforce/apex/paymentSchemeNewButtonController.insertPaymentScheme';
import getPaymentScheme from '@salesforce/apex/paymentSchemeNewButtonController.getPaymentScheme';
import saveInstallmentData from '@salesforce/apex/paymentSchemeNewButtonController.saveInstallmentData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';

import PAYMENT_SCHEME_OBJECT from '@salesforce/schema/Payment_Scheme_Installment__c';
import TYPE_FIELD from '@salesforce/schema/Payment_Scheme_Installment__c.Type__c';


export default class NewPaymentSchemeButton extends LightningElement {
    @api recordId;
    @track companies = [];
    @track selectedCompany = '';
    @track selectedProject;
    @track selectedBlock =[];
    @track name;
    @track tokenAmount;
    @track fromDate;
    @track toDate;
    @track showSpinner = false;

    @track projects = [];
    @track blocks = [];

    @track paymentSchedules = [];
    @track typeOption = [];
    @track rows = [];
    @track renderedRows = [];
    @track showTable = false; 
    @track edit1 = false;
    @track nextButton = true;
    @track saveButton = true;
    @track isButton = false;
    @track isDisabled = false;


    @track isModalOpen = false;
    @track name = '';
    @track installmentCode = '';
    @track installmentSequence = '';
    @track isDisabled1 = false;
    @track companyOptions = [];

    connectedCallback() {
        debugger;
        console.log('recordId:', this.recordId);
        if(this.recordId != ''){
            this.edit1 = true;
            this.nextButton = false;
            this.showTable = true;
        }
        this.fetchCompanies();
        
    }

    objectApiName = PAYMENT_SCHEME_OBJECT;

    @wire(getObjectInfo, { objectApiName: PAYMENT_SCHEME_OBJECT })
    objectInfo;

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: TYPE_FIELD })
    picklistValuesHandler({ data, error }) {
        if (data) {
            this.typeOption = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            console.error('Picklist load error: ', error);
        }
        console.log('this.typeOption==>'+this.typeOption);
    }

    openPopup() {
        debugger;
        this.isModalOpen = true;
    }

    closePopup() {
        debugger;
        this.isModalOpen = false;
    }

    handleInputChange(event) {
        const field = event.target.dataset.id;
        if (field === 'name') {
            this.name = event.target.value;
        } else if (field === 'installmentCode') {
            this.installmentCode = event.target.value;
        } else if (field === 'installmentSequence') {
            this.installmentSequence = event.target.value;
        }
    }


    handleSubmit1() {
        
        debugger;
        
        const installmentData = {
            name: this.name,
            installmentCode: this.installmentCode,
            installmentSequence: this.installmentSequence
        };

        saveInstallmentData({ data: installmentData })
            .then(() => {            
                this.isModalOpen = false;
                this.closePopup();
            })
            .catch(error => {
                console.error('Error saving record:', error);
            });
    }

   

    fetchCompanies() {
        debugger;
        getAllCompanies()
            .then(result => {
                this.companies = result;
                console.log('this.companies==>'+this.companies);

                this.companyOptions = this.companies.map(company => ({
                label: company.Name,
                value: company.Id
            }));

                console.log('this.companyOptions==>'+JSON.stringify(this.companyOptions));
                
                this.fetchPaymentScheme();
                 
            })
            .catch(error => {
                console.error('Error fetching companies:', error);
            });
    }

    handleCompanyChange(event) {
        this.selectedCompany = event.target.value;

            const selectedCompanyOption = this.companyOptions.find(
        (option) => option.value === this.selectedCompany
    );
    console.log('Selected Company Option:', selectedCompanyOption);

        this.fetchProjects();
    }

    handleProjectChange(event) {
        this.selectedProject = event.target.value;
        this.fetchBlocks();
    }

    handleBlockChange(event) {
        debugger;
        this.selectedBlock = event.target.value;
    }

    handleNameChange(event) {
        this.name = event.target.value;
    }

    handleTokenAmountChange(event) {
        this.tokenAmount = event.target.value;
    }

    handleFromDateChange(event) {
        this.fromDate = event.target.value;
    }

    handleToDateChange(event) {
        this.toDate = event.target.value;
    }

    showToast(title, message, variant) {
    const event = new ShowToastEvent({
        title: title,
        message: message,
        variant: variant
    });
    this.dispatchEvent(event);
   }

    handleSubmit() {
        debugger;
        if(!this.selectedBlock || this.selectedBlock.length === 0){
            this.showToast('Validation Error', 'Please select Block', 'error');
            return;
        }
        

        const hasEmptyFields = this.rows.some(row => {
        return !row.selectedSchedule || !row.percentInstallment || !row.displayOrder;
        });

        if (hasEmptyFields) {
        this.showToast('Validation Error', 'Please fill all details for each row: Schedule, Installment, and Display Order.', 'error');
        return; 
        }

        const totalInstallment = this.rows.reduce((sum, row) => {
        return sum + (parseFloat(row.percentInstallment) || 0);
        }, 0);

        if (Math.abs(totalInstallment - 100) > 0.01) {
        this.showToast('Error', 'The total of the installment percentages must be exactly 100%.', 'error');
        return;
        }
        this.showSpinner = true;
        
        const paymentScheme = {
            Id: this.recordId, 
            Name: this.name,
            Token_Amount__c: this.tokenAmount,
            From_Date__c: this.fromDate,
            To_Date__c: this.toDate,
            Company__c: this.selectedCompany,
            Project__c: this.selectedProject,
            
        };

        console.log('paymentScheme==>'+paymentScheme);
       
        const installments = this.rows.map(row => ({
            Id: row.id && typeof row.id === 'string' ? row.id : null, 
            Payment_Schedule_Master__c: row.selectedSchedule,
            Type__c:row.type,
            Installment__c: row.percentInstallment,
            Display_Order__c: row.displayOrder
        }));
        console.log('Installments to be sent:', JSON.stringify(installments));
        console.log('this.selectedBlock==>'+this.selectedBlock);

    insertPaymentScheme({ paymentScheme, installments ,editValue : this.edit1,block : this.selectedBlock})
        .then(paymentSchemeId => {
            console.log('Records inserted successfully, Payment Scheme ID:', paymentSchemeId);
           
            this.isDisabled1 = true;
           this.showToast('Success', 'Records inserted successfully.', 'success');
           this.resetForm();
           this.showSpinner = false;
        })
        .catch(error => {
            console.error('Error inserting records:', error);
            this.showToast('Error', 'Error inserting records: ' + error.body.message, 'error');

            
        });
}

    resetForm() {
        this.selectedCompany = null;
        this.selectedProject = null;
        this.selectedBlock = null;
        this.name = '';
        this.tokenAmount = null;
        this.fromDate = '';
        this.toDate = '';
        this.rows = []; 
        this.renderedRows = []; 
        this.showTable = false; 
        this.addRow();
    }

    @track projectOptions =[];

    fetchProjects() {
        return new Promise((resolve, reject) => {
            if (this.selectedCompany) {
                getProjects({ companyId: this.selectedCompany })
                    .then(result => {
                        console.log('Fetched Projects:', result);
                        this.projects = result;
    
                        if (this.projects.length === 0) {
                            this.projectOptions = [{ label: 'None', value: '' }];
                            // Only set selectedProject to null if necessary
                            if (!this.selectedProject) {
                                this.selectedProject = null;
                            }
                        } else {
                            this.projectOptions = this.projects.map(project => ({
                                label: project.Name,
                                value: project.Id
                            }));
    
                            // Set selectedProject if pre-selected
                            if (this.selectedProject) {
                                const selectedProjectData = this.projects.find(
                                    project => project.Id === this.selectedProject
                                );
                                this.fetchBlocks();
                                if (selectedProjectData) {
                                   // this.selectedProjectLabel = selectedProjectData.Name;
                                }
                            }
                        }
                        this.blocks = [];
                        resolve(); // Resolving after fetching projects
                    })
                    .catch(error => {
                        console.error('Error fetching projects:', error);
                        reject(error);
                    });
            }
        });
    }


get selectedProjectLabel() {
    const selected = this.projectOptions.find(option => option.value === this.selectedProject);
    return selected ? selected.label : '';
}



    // get projectOptions() {
    //     if (this.projects.length === 0) {
    //         return [{ label: 'None', value: '' }];
    //     }
    //     return this.projects.map(project => ({
    //         label: project.Name,
    //         value: project.Id
    //     }));
    // }


@track blockOptions =[];
fetchBlocks() {
    debugger;
    if (this.selectedProject) {
        getBlocks({ projectId: this.selectedProject })
            .then(result => {
                this.blocks = result;
                
                if (this.blocks.length === 0) {
                    this.blockOptions = [{ label: 'None', value: '' }];
                } else {
                    // Populate block options
                    this.blockOptions = this.blocks.map(block => ({
                        label: block.Name,
                        value: block.Id
                    }));
                    
                    // Set selectedBlock if available
                    if (this.selectedBlock && this.selectedBlock.length > 0) {
                        // Pre-select the blocks by setting selectedBlock
                        this.selectedBlock = this.selectedBlock.filter(blockId => 
                            this.blockOptions.some(option => option.value === blockId)
                        );
                    }
                }
            })
            .catch(error => {
                console.error('Error fetching blocks:', error);
            });
    }
}



get selectedBlockLabel() {
    const selected = this.blockOptions.find(option => option.value === this.selectedBlock);
    return selected ? selected.label : '';
}

    

    

    // get blockOptions() {
    //     if (this.blocks.length === 0) {
    //         return [{ label: 'None', value: '' }];
    //     }
    //     return this.blocks.map(block => ({
    //         label: block.Name,
    //         value: block.Id
    //     }));
    // }
    @wire(getPaymentScheduleOptions)
    wiredPaymentSchedules({ error, data }) {
        if (data) {
            this.paymentSchedules = data.map(schedule => ({
                label: schedule.Name,
                value: schedule.Id
            }));
            
            if (this.rows.length === 0) {
                this.addRow(); 
            }
        } else if (error) {
            console.error('Error fetching payment schedules:', error);
        }
    }


    addRow() {
        const newRow = {
            id: Date.now(), 
            selectedSchedule: '',
            type:'Agreement',
            percentInstallment: '',
            displayOrder: ''
        };
        this.rows = [...this.rows, newRow];
        this.updateRenderedRows();
        console.log('Added row:', JSON.stringify(newRow));
    }

    
    handleScheduleChange(event) {
        debugger;
        const rowId = event.target.dataset.id;
        const selectedSchedule = event.detail.value;

        console.log('this.rows-->'+this.rows);
        this.rows = this.rows.map(row => {
            if (row.id == rowId) { 
                return { ...row, selectedSchedule };
            }
            return row;
        });
        console.log('this.rows-->'+this.rows);
        this.updateRenderedRows();
    }

    // handlePercentChange(event) {
    //     const rowId = event.target.dataset.id;
    //     const percentInstallment = event.target.value;

    //     this.rows = this.rows.map(row => {
    //         if (row.id === Number(rowId)) { 
    //             return { ...row, percentInstallment };
    //         }
    //         return row;
    //     });
    //     this.updateRenderedRows();
    // }
    handlePercentChange(event) {
        debugger;
        const rowId = event.target.dataset.id;
        const percentInstallment = event.target.value;
        
        if (percentInstallment < 0) {
        event.target.value = ''; 
        return;
        }
        this.rows = this.rows.map(row => {
            if (row.id == rowId) {
                return { ...row, percentInstallment };
            }
            return row;
        });
        console.log('Rows after percent change:', JSON.stringify(this.rows));
        this.updateRenderedRows();
    }

    handleNext() {
        if (!this.name || !this.tokenAmount || !this.fromDate || !this.toDate || !this.selectedCompany || !this.selectedProject || !this.selectedBlock) {
        // Show toast message
        const event = new ShowToastEvent({
            title: 'Validation Error',
            message: 'Please enter all required fields.',
            variant: 'error'
        });
        this.dispatchEvent(event);
        return; 
      }   

        debugger;
        if (this.rows.length === 0) {
            this.addRow();
        }
        this.showTable = true; 
        
        
    }

    // handleDisplayOrderChange(event) {
    //     debugger;
    //     const rowId = event.target.dataset.id;
    //     const displayOrder = event.target.value;
    //     console.log('disolay order change :', displayOrder);
    //     this.rows = this.rows.map(row => {
    //         if (row.id === Number(rowId)) {
    //             return { ...row, displayOrder };
    //         }
    //         return row;
    //     });
    //     this.updateRenderedRows();
    // }
    handleDisplayOrderChange(event) {
        debugger;
        const rowId = event.target.dataset.id;
        const displayOrder = event.target.value;
        console.log('Display order change:', displayOrder);

        this.rows = this.rows.map(row => {
            if (row.id == rowId) {
                return { ...row, displayOrder };
            }
            return row;
        });
        console.log('Rows after display order change:', JSON.stringify(this.rows));
        this.updateRenderedRows();
    }

    handleTypeChange(event) {
        debugger;
        console.log('this.rows==>'+this.rows);
        const rowId = Number(event.target.dataset.id); 
        const selectedType = event.target.value;

        
        this.rows = this.rows.map(row => {
            if (row.id === rowId) {
                return { ...row, type: selectedType };
            }
            return row;
        });

        console.log('Updated row:', rowId, 'to type:', selectedType);
           this.updateRenderedRows();
    }


    handleDeleteRow(event) {
        console.log('Delete button clicked:', event);
        const rowId = event.currentTarget.dataset.id; 
        console.log('Raw data-id:', rowId);
        
        const parsedId = Number(rowId); 
        console.log('Parsed row ID:', parsedId);
        
        if (!isNaN(parsedId)) {
            if (this.rows.length > 1) { 
                this.rows = this.rows.filter(row => row.id !== parsedId);
                this.updateRenderedRows();
                console.log('Remaining rows after deletion:', this.rows);
            } else {
                console.warn('Cannot delete the last row. At least one row must remain.');
            }
        } else {
            console.error('Invalid row ID for deletion:', rowId);
        }
    }
    

    handleAddRow() {
        this.addRow();
    }

    updateRenderedRows() {
        debugger;
        this.renderedRows = this.rows.map((row, index) => ({
            ...row,
            index: index + 1
        }));
        console.log('this.renderedRows===>'+this.renderedRows);
    }

    
    @track  approval = false;
    fetchPaymentScheme() {
        debugger;
        if (this.recordId) {
            getPaymentScheme({ recordId: this.recordId })
                .then(result => {
                    if (result) {
                        const paymentScheme = result.paymentSchemes[0];
                        const paymentInstallments = result.paymentInstallments;
                        this.selectedBlock = paymentScheme.Tower__c;
    
                        // Check approval status and set button states
                        if (paymentScheme.Approval_Status__c === 'Approved') {
                            this.approval = true;
                            this.saveButton = false;
                            this.isButton = true;
                        }
    
                        if (paymentScheme) {
                            this.name = paymentScheme.Name;
                            this.tokenAmount = paymentScheme.Token_Amount__c;
                            this.fromDate = paymentScheme.From_Date__c;
                            this.toDate = paymentScheme.To_Date__c;
    
                            // Set selectedCompany
                            this.selectedCompany = paymentScheme.Company__c;
    
                            // Set selectedProject (new change here)
                            this.selectedProject = paymentScheme.Project__c;
    
                            // Set selectedBlock (new change here)
                            this.selectedBlock = paymentScheme.Blockc__c ? paymentScheme.Blockc__c.map(block => block.Id) : [];
                            //this.selectedBlock = paymentScheme.Block__c;
                            console.log('this.selectedCompany after fetch==>', this.selectedCompany);
                            console.log('this.selectedProject after fetch==>', this.selectedProject);
                            console.log(' this.selectedBlock after fetch==>', this.selectedBlock);
                            
                            // Fetch projects if necessary (especially important if the selectedCompany changes)
                            this.fetchProjects().then(() => {
                                // Ensure blocks are fetched after projects
                                this.fetchBlocks(); // Fetch blocks even if it's in edit mode
                            });
                        } else {
                            console.warn('No payment scheme found for the given recordId.');
                        }
    
                        // Process installments if available
                        if (paymentInstallments && paymentInstallments.length > 0) {
                            this.rows = paymentInstallments.map(installment => ({
                                id: installment.Id,
                                selectedSchedule: installment.Payment_Schedule_Master__c,
                                 type :installment.Type__c,
                                percentInstallment: installment.Installment__c,
                                displayOrder: installment.Display_Order__c
                            }));
                            this.updateRenderedRows();
                        } else {
                            console.warn('No payment installments found for the given payment scheme.');
                        }
                    } else {
                        console.warn('No payment scheme data returned for the given recordId.');
                    }
                })
                .catch(error => {
                    console.error('Error fetching payment scheme:', error);
                });
        }
    }
    
    
    
 
}