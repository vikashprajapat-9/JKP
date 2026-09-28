import { LightningElement, track ,api} from 'lwc';
import getCostSheetData from '@salesforce/apex/PaymentSchemeCostSheetLinkingController.getCostSheetData';
import getCostSheetExisData from '@salesforce/apex/PaymentSchemeCostSheetLinkingController.getCostSheetExisData';
import submitData from '@salesforce/apex/PaymentSchemeCostSheetLinkingController.submitData';
import updateData from '@salesforce/apex/PaymentSchemeCostSheetLinkingController.updateData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class PaymentSchemeCostSheetLinking extends NavigationMixin(LightningElement)  {
    @track data=[];
    @track zCodeValue = '';
    @track companyOptions = [];
    @track projectOptions = [];
    @track blockOptions = [];
    @track paymentSchemeOptions=[];
    @track costSheetTemplateOptions=[];
    @track companyValue = '';
    @track projectValue = '';
    @track blockValue = '';
    @track paymentSchemeValue = '';
    @track costSheetTemplateValue ='';
    @track paymentFrom ='';
    @track paymentTo ='';
    @track differDays ='';
    @track projectData = []; 
    @track blockData =[];
    @track paymentSchemeData = [];
    @track costSheetData =[];
    @track error;
     @track schemaArr = [];
     @track schemaArr1 = false;
     @api recordId;
     @track editmode = false;
     @track errorMessage = '';
     @track isInstallmentDisable = false;
     @track editmode1 = false;
     @track costLinkId = '';
     @track isCreate = false;

     @track isApproval = false;

      connectedCallback() {
        debugger;
        console.log('this.recordId==>'+this.recordId);
         this.fetchCompanyData();
        
    }

    handleZCodeChange(event) {
        this.zCodeValue = event.target.value;
        console.log('ZCode==>',this.zCodeValue);
    }


     fetchCompanyData() {
        debugger;
        getCostSheetData()
            .then((result) => {
                
                this.companyOptions = result.companyNames.map(company => ({
                    label: company.Name,
                    value: company.Id
                }));
                this.data = result;
                
                this.projectData = result.projectNames;
                this.blockData = result.towerNames;
                this.paymentSchemeData =  result.paymentSchemes;
                this.costSheetData = result.costSheetNames;

                 if(this.recordId != ''){
                  this.fetchCostSchemeData();
                    this.editmode = false;
                    }
            })
            .catch((error) => {
                this.error = error;
            });

           
    }


    
   
    @track isComboboxDisabled = false;
    fetchCostSchemeData() {
        debugger;
        this.editmode = true;
        getCostSheetExisData({costSchemeId : this.recordId })
            .then((result) => {
                console.log('result===>'+result);
                const { costSchemeLinking, schemeInstallments1 } = result;
                this.costSchemeLinking = costSchemeLinking;
            this.schemeInstallments = schemeInstallments1;
            this.companyValue = this.costSchemeLinking.Cost_Sheet_Template__r.Company__c;
            this.projectValue = this.costSchemeLinking.Cost_Sheet_Template__r.Project__c;
            this.blockValue = this.costSchemeLinking.Payment_Scheme__r.Block__c;
            this.paymentSchemeValue = this.costSchemeLinking.Payment_Scheme__r.Id;
            this.costSheetTemplateValue = this.costSchemeLinking.Cost_Sheet_Template__c;

            console.log('costSchemeLinking:', this.costSchemeLinking);
            console.log('schemeInstallments:', this.schemeInstallments);
            
            console.log('this.projectData-->'+this.projectData);
                
            this.projectOptions = this.projectData
                .filter(project => project.Company__c === this.companyValue)
                .map(project => ({
                    label: project.Name,
                    value: project.Id
                }));

          
             console.log('this.projectOptions==>'+this.projectOptions);
             if(this.projectValue){
                const matchingProject = this.projectOptions.find(
                    project => project.value === this.projectValue
                );
                console.log('matchingProject==>'+matchingProject);
                if (matchingProject) {
                    this.projectValue = matchingProject.value; // Set the value for combobox selection
                    console.log('Selected Project Label:', matchingProject.label);
                }
             }


             this.blockOptions = this.blockData
                .filter(tower => tower.Project__c === this.projectValue)
                .map(project => ({
                    label: project.Name,
                    value: project.Id
                }));

                console.log('this.blockOptions==>'+this.blockOptions);
                if(this.blockValue){
                    const matchingblock = this.blockOptions.find(
                        project => project.value === this.blockValue
                    );
                    console.log('matchingblock==>'+matchingblock);
                    if (matchingblock) {
                        this.blockValue = matchingblock.value; // Set the value for combobox selection
                        console.log('Selected Project Label:', matchingblock.label);
                    }

                }

                this.paymentSchemeOptions = this.paymentSchemeData
                .filter(paymentScheme => paymentScheme.Block__c === this.blockValue && paymentScheme.Project__c === this.projectValue && paymentScheme.Company__c === this.companyValue)
                .map(tower => ({
                    label: tower.Name,
                    value: tower.Id
                }));

                console.log('this.paymentSchemeOptions==>'+this.paymentSchemeOptions);

                if(this.paymentSchemeValue){

                    const matchingpaymentscheme = this.paymentSchemeOptions.find(
                        project => project.value === this.paymentSchemeValue
                    );
                    console.log('matchingpaymentscheme==>'+matchingpaymentscheme);
                    if (matchingpaymentscheme) {
                        this.paymentSchemeValue = matchingpaymentscheme.value; // Set the value for combobox selection
                        console.log('Selected Project Label:', matchingpaymentscheme.label);

                    }


                }

                console.log('this.paymentSchemeData==>'+this.paymentSchemeData);
                console.log('paymentSchemeValue==>'+this.paymentSchemeValue);
                const selectedPaymentScheme = this.paymentSchemeData.find(
                    paymentScheme => paymentScheme.Id === this.paymentSchemeValue
                );

                console.log('selectedPaymentScheme==>'+selectedPaymentScheme);
            
                if (selectedPaymentScheme) {
                    this.paymentFrom = selectedPaymentScheme.From_Date__c;
                    this.paymentTo = selectedPaymentScheme.To_Date__c;
                    //this.differDays = selectedPaymentScheme.Installment_start_date_diff_in_days__c;
                }

                this.costSheetTemplateoptions = this.data.costSheetNames
                .filter(tower => tower.Project__c === this.projectValue  && tower.Company__c === this.companyValue)
                    .map(project => ({
                        label: project.Name,
                        value: project.Id
                    }));

                    console.log('this.costSheetTemplateoptions==>'+this.costSheetTemplateoptions);

                    if(this.costSheetTemplateValue){

                        const matchingpaymentscheme = this.costSheetTemplateoptions.find(
                            project => project.value === this.costSheetTemplateValue
                        );
                        console.log('matchingpaymentscheme==>'+matchingpaymentscheme);
                        if (matchingpaymentscheme) {
                            this.costSheetTemplateValue = matchingpaymentscheme.value; // Set the value for combobox selection
                            console.log('Selected Project Label:', matchingpaymentscheme.label);
    
                        }
    
    
                    }

                    this.schemaArr1 = true;
                    console.log('schemaArr1===>'+this.schemaArr1);
                    this.schemaArr = this.schemeInstallments;
                    console.log('schemaArr===>'+this.schemaArr);



                     // Calculate totals
                this.schemaArr.forEach(item => {
                this.totalInstallmentPercent += item.Installment__c || 0;
                this.agrrementValue += item.Agreement_Value__c || 0;
                this.agreementTax += item.Agreement_Tax__c || 0;
            });

            console.log('Total Installment Percent:', this.totalInstallmentPercent);
            console.log('Total Agreement Value:', this.agrrementValue);
            console.log('Total Agreement Tax:', this.agreementTax);

            
            if(this.costSchemeLinking.Approval_Status__c == 'Approved'){
                this.isComboboxDisabled = true;
                this.isInstallmentDisable = true;
                this.editmode = false;
                this.editmode1 = true;
            }else{
                this.editmode = true;
            }

                    


                
            })
            .catch((error) => {
                this.error = error;
            });
    }

   
    handleChange(event) {
        debugger;
        const field = event.target.name;

        if (field === 'company') {
            this.companyValue = event.target.value;

            this.projectOptions = this.projectData
                .filter(project => project.Company__c === this.companyValue)
                .map(project => ({
                    label: project.Name,
                    value: project.Id
                }));

            this.projectValue = '';
            this.costSheetTemplateValue ='';
            this.paymentSchemeValue = '';
            this.blockOptions = [];

        } else if (field === 'project') {
            this.projectValue = event.target.value;
            console.log('this.data.towerNames==>'+this.data.towerNames);

            this.blockOptions = this.data.towerNames
                .filter(tower => tower.Project__c === this.projectValue)
                .map(project => ({
                    label: project.Name,
                    value: project.Id
                }));
            
            console.log('blockOptions==>'+this.blockOptions);
            this.blockValue = '';
            this.paymentSchemeValue = '';

            this.costSheetTemplateoptions = this.costSheetData
            .filter(tower => tower.Project__c === this.projectValue  && tower.Company__c === this.companyValue)
                .map(project => ({
                    label: project.Name,
                    value: project.Id
                }));

                console.log('costSheetTemplateoptions==>'+this.costSheetTemplateoptions);


        } else if (field === 'block') {
            this.blockValue = event.target.value;
            
            console.log('blockValue==>'+this.blockValue);
            console.log('this.data.towerNames==>'+this.data.paymentSchemes);

            this.paymentSchemeOptions = this.data.paymentSchemes
                .filter(paymentScheme => paymentScheme.Block__c === this.blockValue && paymentScheme.Project__c === this.projectValue && paymentScheme.Company__c === this.companyValue)
                .map(tower => ({
                    label: tower.Name,
                    value: tower.Id
                }));
        }else if(field === 'paymentScheme'){
            this.paymentSchemeValue = event.target.value;

            const selectedPaymentScheme = this.data.paymentSchemes.find(
                paymentScheme => paymentScheme.Id === this.paymentSchemeValue
            );
        
            if (selectedPaymentScheme) {
                this.paymentFrom = selectedPaymentScheme.From_Date__c;
                this.paymentTo = selectedPaymentScheme.To_Date__c;
                this.differDays = selectedPaymentScheme.Installment_start_date_diff_in_days__c;
            }
           
        }else if(field === 'costSheetTemplate'){
            this.costSheetTemplateValue = event.target.value;
        }
}



   @track totalInstallmentPercent = 0;
   @track agrrementValue = 0;
   @track agreementTax = 0;


handleSubmit() {
    debugger;
    console.log('paymentSchemeValue ==> ', this.paymentSchemeValue);
    console.log('costSheetTemplateValue ==> ', this.costSheetTemplateValue);
    console.log('zCodeValue ==> ', this.zCodeValue);
    const paymentSchemeId = this.paymentSchemeValue;
    const costSheetId = this.costSheetTemplateValue;
    const zCode = this.zCodeValue;  // Add the zCode here
    submitData({ paymentSchemeId, costSheetId, zCode })  // Pass zCode to Apex
        .then(result => {
            this.errorMessage = '';
            this.schemaArr = result;
            this.costLinkId = result[0].Cost_Scheme_Linking__c;
            console.log('this.costLinkId==>' + this.costLinkId);
            this.schemaArr1 = true;
            console.log(result);

            this.totalInstallmentPercent = 0;
            this.agrrementValue = 0;
            this.agreementTax = 0;

            // Calculate totals
            this.schemaArr.forEach(item => {
                this.totalInstallmentPercent += item.Installment__c || 0;
                this.agrrementValue += item.Agreement_Value__c || 0;
                this.agreementTax += item.Agreement_Tax__c || 0;
            });

            console.log('Total Installment Percent:', this.totalInstallmentPercent);
            console.log('Total Agreement Value:', this.agrrementValue);
            console.log('Total Agreement Tax:', this.agreementTax);

            this.showToast('Success', 'Scheme Installments Created Successfully..', 'success');
            this.isCreate = true;
        })
        .catch(error => {
            this.errorMessage = error.body.message;
            console.error('Error:', error);
            this.showToast('Error', 'Something went wrong!', 'error');
        });
}


    handleupdate(event){
        debugger;
        if(!this.zCodeValue){
            this.showToast('Error', 'Please enter Zcode Before Saving the record', 'error');
        }else{

            const paymentSchemeId  = this.paymentSchemeValue;
        const costSheetId = this.costSheetTemplateValue;
        const ZCode = this.zCodeValue;

            updateData({  paymentSchemeId, costSheetId,schemeId : this.recordId,costSheetIdNew : this.costLinkId, ZCode})
            .then(result => {

                this.schemaArr = result;
                this.schemaArr1 = true;
                console.log(result); 

                this.totalInstallmentPercent = 0;
                this.agrrementValue = 0;
                this.agreementTax = 0;

                this.schemaArr.forEach(item => {
                    this.totalInstallmentPercent += item.Installment__c || 0;
                    this.agrrementValue += item.Agreement_Value__c || 0;
                    this.agreementTax += item.Agreement_Tax__c || 0;
                });

                console.log('Total Installment Percent:', this.totalInstallmentPercent);
                console.log('Total Agreement Value:', this.agrrementValue);
                console.log('Total Agreement Tax:', this.agreementTax);
                this.showToast('Success', 'Approval sent Successfully..', 'success');
                this.isApproval = true;

                console.log('Navigating to record:', this.costLinkId);
                this. handleButtonClick();

            })
            .catch(error => {
                console.error('Error:', error);
                
            });
        }
            
        }

    handleButtonClick() {
        debugger;
        // console.log('Navigating to Record ID:', this.costLinkId);
        //  if (this.costLinkId) {
        //     const url = `https://snnestates--snnsandbox.sandbox.lightning.force.com/lightning/r/Cost_Scheme_Linking__c/${this.costLinkId}/view`;
        //     console.log('Navigating to Record:', this.costLinkId);
        //    window.location.replace(url);
             
            
        // } 

        if (this.costLinkId) {
            // Construct the URL for the record page
            const recordUrl = `/lightning/r/Cost_Scheme_Linking__c/${this.costLinkId}/view`;

            // Navigate to the record page using window.location
            window.top.location.href = recordUrl;
        }

    // if(this.costLinkId){
    //     debugger;
    // this[NavigationMixin.Navigate]({
    //         type: 'standard__recordPage',
    //         attributes: {
    //             recordId: this.costLinkId,
    //              objectApiName: 'Cost_Scheme_Linking__c',
    //             actionName: 'view'
    //         }
    //     });
    // }
         
        
    }


     showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }


}