({
    adjustModalDimensions : function(component) {
        window.setTimeout(
            $A.getCallback(function () {
                if (!component.isValid()) {
                    return;
                }
                var el = component.getElement();
                if (!el) {
                    return;
                }

                // Target the modal content and container elements
                var modalContent = el.closest ? el.closest('.slds-modal__content') : null;
                var modalContainer = el.closest ? el.closest('.slds-modal__container') : null;

                if (modalContent) {
                    modalContent.style.height = 'auto';
                    modalContent.style.minHeight = 'auto';
                    modalContent.style.maxHeight = '65vh';
                    modalContent.style.overflowY = 'auto';
                    modalContent.style.padding = '0';
                    modalContent.style.borderRadius = '8px';
                }

                if (modalContainer) {
                    modalContainer.style.height = 'auto';
                    modalContainer.style.minHeight = 'auto';
                    modalContainer.style.maxHeight = '90vh';
                    modalContainer.style.width = '90%';
                    modalContainer.style.maxWidth = '52rem';
                    modalContainer.style.minWidth = '20rem';
                    modalContainer.style.margin = '0 auto';
                    modalContainer.style.display = 'flex';
                    modalContainer.style.flexDirection = 'column';
                    modalContainer.style.justifyContent = 'center';
                }
            }),
            50
        );
    },

    navigateToLwc : function(component, oppId) {
        var navService = component.find("navService");
        var pageReference = {
            type: 'standard__component',
            attributes: {
                componentName: 'c__bookingForm' 
            },
            state: {
                c__recordId: oppId
            }
        };
        navService.navigate(pageReference);
    }
})