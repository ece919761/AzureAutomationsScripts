{
  "properties": {
    "displayName": "Backup - AzureVirtualDesktopSessionHost",
    "policyType": "Custom",
    "mode": "Indexed",
    "description": "Azure Backup for Virtual Machines tagged for backup in 'Digital - Azure Virtual Desktops' subscriptions",
    "metadata": {
      "category": "Backup",
      "createdBy": "aef8c30a-4591-4ee9-b28a-3dc2728d6c3e",
      "createdOn": "2026-07-01T08:24:36.3327115Z",
      "updatedBy": "aef8c30a-4591-4ee9-b28a-3dc2728d6c3e",
      "updatedOn": "2026-07-07T03:34:46.7397932Z"
    },
    "version": "1.0.0",
    "parameters": {
      "vaultLocation": {
        "type": "String",
        "metadata": {
          "displayName": "Vault Location",
          "description": "Azure region containing the VM and Recovery Services Vault",
          "strongType": "location"
        }
      },
      "backupPolicyId": {
        "type": "String",
        "metadata": {
          "displayName": "Backup Policy ID",
          "description": "Recovery Services Vault Azure VM backup policy",
          "strongType": "Microsoft.RecoveryServices/vaults/backupPolicies"
        }
      },
      "effect": {
        "type": "String",
        "allowedValues": [
          "DeployIfNotExists",
          "AuditIfNotExists",
          "Disabled"
        ],
        "defaultValue": "DeployIfNotExists"
      }
    },
    "policyRule": {
      "if": {
        "allOf": [
          {
            "field": "type",
            "equals": "Microsoft.Compute/virtualMachines"
          },
          {
            "field": "location",
            "equals": "[parameters('vaultLocation')]"
          },
          {
            "field": "[concat('tags[','BackupPlan',']')]",
            "in": [
              "Azure-VDI-DAILY-30D",
              "Azure-SU-DAILY-30D"
            ]
          }
        ]
      },
      "then": {
        "effect": "[parameters('effect')]",
        "details": {
          "roleDefinitionIds": [
            "/providers/microsoft.authorization/roleDefinitions/9980e02c-c2be-4d73-94e8-173b1dc7cf3c",
            "/providers/microsoft.authorization/roleDefinitions/5e467623-bb1f-42f4-a55d-6e525e11384b"
          ],
          "type": "Microsoft.RecoveryServices/backupprotecteditems",
          "existenceCondition": {
            "field": "name",
            "like": "*"
          },
          "deployment": {
            "properties": {
              "mode": "incremental",
              "template": {
                "$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
                "contentVersion": "1.0.0.0",
                "parameters": {
                  "backupPolicyId": {
                    "type": "String"
                  },
                  "fabricName": {
                    "type": "String"
                  },
                  "protectionContainers": {
                    "type": "String"
                  },
                  "protectedItems": {
                    "type": "String"
                  },
                  "sourceResourceId": {
                    "type": "String"
                  }
                },
                "resources": [
                  {
                    "apiVersion": "2017-05-10",
                    "name": "[concat('DeployProtection-',uniqueString(parameters('protectedItems')))]",
                    "type": "Microsoft.Resources/deployments",
                    "resourceGroup": "[first(skip(split(parameters('backupPolicyId'), '/'), 4))]",
                    "subscriptionId": "[first(skip(split(parameters('backupPolicyId'), '/'), 2))]",
                    "properties": {
                      "mode": "Incremental",
                      "template": {
                        "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
                        "contentVersion": "1.0.0.0",
                        "parameters": {
                          "backupPolicyId": {
                            "type": "String"
                          },
                          "fabricName": {
                            "type": "String"
                          },
                          "protectionContainers": {
                            "type": "String"
                          },
                          "protectedItems": {
                            "type": "String"
                          },
                          "sourceResourceId": {
                            "type": "String"
                          }
                        },
                        "resources": [
                          {
                            "type": "Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems",
                            "name": "[concat(first(skip(split(parameters('backupPolicyId'), '/'), 8)), '/', parameters('fabricName'), '/',parameters('protectionContainers'), '/', parameters('protectedItems'))]",
                            "apiVersion": "2016-06-01",
                            "properties": {
                              "protectedItemType": "Microsoft.Compute/virtualMachines",
                              "policyId": "[parameters('backupPolicyId')]",
                              "sourceResourceId": "[parameters('sourceResourceId')]"
                            }
                          }
                        ]
                      },
                      "parameters": {
                        "backupPolicyId": {
                          "value": "[parameters('backupPolicyId')]"
                        },
                        "fabricName": {
                          "value": "[parameters('fabricName')]"
                        },
                        "protectionContainers": {
                          "value": "[parameters('protectionContainers')]"
                        },
                        "protectedItems": {
                          "value": "[parameters('protectedItems')]"
                        },
                        "sourceResourceId": {
                          "value": "[parameters('sourceResourceId')]"
                        }
                      }
                    }
                  }
                ]
              },
              "parameters": {
                "backupPolicyId": {
                  "value": "[parameters('backupPolicyId')]"
                },
                "fabricName": {
                  "value": "Azure"
                },
                "protectionContainers": {
                  "value": "[concat('iaasvmcontainer;iaasvmcontainerv2;', resourceGroup().name, ';' ,field('name'))]"
                },
                "protectedItems": {
                  "value": "[concat('vm;iaasvmcontainerv2;', resourceGroup().name, ';' ,field('name'))]"
                },
                "sourceResourceId": {
                  "value": "[concat('/subscriptions/', subscription().subscriptionId, '/resourceGroups/', resourceGroup().name, '/providers/Microsoft.Compute/virtualMachines/',field('name'))]"
                }
              }
            }
          }
        }
      }
    },
    "versions": [
      "1.0.0"
    ]
  },
  "id": "/providers/microsoft.management/managementgroups/f66b6bd3-ebc2-4f54-8769-d22858de97c5/providers/Microsoft.Authorization/policyDefinitions/8a2d075bdb0f4e1291eb0b75",
  "type": "Microsoft.Authorization/policyDefinitions",
  "name": "8a2d075bdb0f4e1291eb0b75",
  "systemData": {
    "createdBy": "KDhara3.sso@harman.com",
    "createdByType": "User",
    "createdAt": "2026-07-01T08:24:36.1552376Z",
    "lastModifiedBy": "KDhara3.sso@harman.com",
    "lastModifiedByType": "User",
    "lastModifiedAt": "2026-07-07T03:34:46.7237509Z"
  }
}