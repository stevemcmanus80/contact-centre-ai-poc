data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_dynamodb_table" "contact_centre_cases" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ReferenceNumber"

  attribute {
    name = "ReferenceNumber"
    type = "S"
  }
}

resource "aws_lambda_function" "lex_orchestrator" {

  function_name = var.lambda_function_name

  role    = "arn:aws:iam::533140817207:role/service-role/lex_orchestrator-role-cad9eis1"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.12"

  filename         = "../lambda.zip"
  source_code_hash = filebase64sha256("../lambda.zip")

  timeout     = 3
  memory_size = 128

  environment {
    variables = {
      DYNAMODB_TABLE   = var.dynamodb_table_name
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }
}

resource "aws_iam_role" "lex_orchestrator" {
  name = "lex_orchestrator-role-cad9eis1"
  path = "/service-role/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_basic_execution" {
  name = "AWSLambdaBasicExecutionRole-5d8eefc3-1af0-453d-a460-fdbda07c5dbe"
  path = "/service-role/"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:eu-west-2:533140817207:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:eu-west-2:533140817207:log-group:/aws/lambda/lex_orchestrator:*"
        ]
      }
    ]
  })
}

data "aws_iam_policy" "dynamodb_read_only" {
  arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "dynamodb_read_only" {
  role       = aws_iam_role.lex_orchestrator.name
  policy_arn = data.aws_iam_policy.dynamodb_read_only.arn
}

resource "aws_iam_role_policy" "bedrock_invoke_model" {
  name = "BedrockInvokeModelPolicy"
  role = aws_iam_role.lex_orchestrator.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lex_orchestrator" {
  name = "/aws/lambda/lex_orchestrator"
}

resource "aws_lexv2models_bot" "contact_centre_ai" {
  name        = "ContactCentreAI"
  description = "AI Contact Centre PoC for Amazon Connect"

  data_privacy {
    child_directed = false
  }

  idle_session_ttl_in_seconds = 300

  role_arn = "arn:aws:iam::533140817207:role/service-role/AmazonLexServiceRole-ZSN466DOR9"
  type     = "Bot"

  tags = {
    AmazonConnectEnabled = "True"
  }
}

resource "aws_lexv2models_bot_locale" "en_gb" {
  bot_id                           = aws_lexv2models_bot.contact_centre_ai.id
  bot_version                      = "DRAFT"
  locale_id                        = "en_GB"
  n_lu_intent_confidence_threshold = 0.4

  voice_settings {
    engine   = "neural"
    voice_id = "Amy"
  }
}

resource "aws_lexv2models_intent" "check_case_status" {
  bot_id      = aws_lexv2models_bot.contact_centre_ai.id
  bot_version = aws_lexv2models_bot_locale.en_gb.bot_version
  locale_id   = aws_lexv2models_bot_locale.en_gb.locale_id

  name = "CheckCaseStatus"

  sample_utterance {
    utterance = "Where is my claim?"
  }

  sample_utterance {
    utterance = "Check my case"
  }

  sample_utterance {
    utterance = "What's happening with my application?"
  }

  sample_utterance {
    utterance = "Can you tell me my claim status?"
  }

  sample_utterance {
    utterance = "I want to check my benefit"
  }

  sample_utterance {
    utterance = "Has my application been processed?"
  }

  sample_utterance {
    utterance = "Any update on my case?"
  }

  sample_utterance {
    utterance = "Check my review status"
  }

  dialog_code_hook {
    enabled = false
  }

  fulfillment_code_hook {
    enabled = true
    active  = true

    post_fulfillment_status_specification {
      success_next_step {
        dialog_action {
          type = "EndConversation"
        }
      }

      failure_next_step {
        dialog_action {
          type = "EndConversation"
        }
      }

      timeout_next_step {
        dialog_action {
          type = "EndConversation"
        }
      }
    }
  }

  initial_response_setting {
    next_step {
      dialog_action {
        type = "InvokeDialogCodeHook"
      }
    }

    code_hook {
      enable_code_hook_invocation = true
      active                      = true

      post_code_hook_specification {
        success_next_step {
          dialog_action {
            type           = "ElicitSlot"
            slot_to_elicit = "ReferenceNumber"
          }
        }

        failure_next_step {
          dialog_action {
            type = "EndConversation"
          }
        }

        timeout_next_step {
          dialog_action {
            type = "EndConversation"
          }
        }
      }
    }
  }
}

resource "aws_lexv2models_slot" "check_case_status_reference_number" {
  bot_id      = aws_lexv2models_bot.contact_centre_ai.id
  bot_version = aws_lexv2models_bot_locale.en_gb.bot_version
  intent_id   = aws_lexv2models_intent.check_case_status.intent_id
  locale_id   = aws_lexv2models_bot_locale.en_gb.locale_id
  name        = "ReferenceNumber"

  slot_type_id = "AMAZON.AlphaNumeric"

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      max_retries                = 4
      allow_interrupt            = true
      message_selection_strategy = "Random"

      message_group {
        message {
          plain_text_message {
            value = "Can I have your reference number?"
          }
        }
      }
    }
  }
}

resource "aws_lexv2models_intent" "speak_to_adviser" {
  bot_id      = aws_lexv2models_bot.contact_centre_ai.id
  bot_version = aws_lexv2models_bot_locale.en_gb.bot_version
  locale_id   = aws_lexv2models_bot_locale.en_gb.locale_id

  name = "SpeakToAdviser"

  sample_utterance {
    utterance = "Speak to someone"
  }

  sample_utterance {
    utterance = "I need an adviser"
  }

  sample_utterance {
    utterance = "Put me through"
  }

  sample_utterance {
    utterance = "Transfer me"
  }

  sample_utterance {
    utterance = "Human please"
  }

  sample_utterance {
    utterance = "Can I talk to an agent?"
  }

  sample_utterance {
    utterance = "I'd like to speak to somebody"
  }

  sample_utterance {
    utterance = "Connect me to an adviser"
  }

  dialog_code_hook {
    enabled = false
  }

  fulfillment_code_hook {
    enabled = true
    active  = true

    post_fulfillment_status_specification {
      success_next_step {
        dialog_action {
          type = "EndConversation"
        }
      }

      failure_next_step {
        dialog_action {
          type = "EndConversation"
        }
      }

      timeout_next_step {
        dialog_action {
          type = "EndConversation"
        }
      }
    }
  }

  initial_response_setting {
    next_step {
      dialog_action {
        type = "InvokeDialogCodeHook"
      }
    }

    code_hook {
      enable_code_hook_invocation = true
      active                      = true

      post_code_hook_specification {
        success_next_step {
          dialog_action {
            type = "FulfillIntent"
          }
        }

        failure_next_step {
          dialog_action {
            type = "EndConversation"
          }
        }

        timeout_next_step {
          dialog_action {
            type = "EndConversation"
          }
        }
      }
    }
  }
}

resource "aws_lexv2models_intent" "request_document" {
  bot_id      = aws_lexv2models_bot.contact_centre_ai.id
  bot_version = aws_lexv2models_bot_locale.en_gb.bot_version
  locale_id   = aws_lexv2models_bot_locale.en_gb.locale_id

  name = "RequestDocument"

  sample_utterance {
    utterance = "Send me another letter"
  }

  sample_utterance {
    utterance = "I lost my documents"
  }

  sample_utterance {
    utterance = "Can I have another copy"
  }

  sample_utterance {
    utterance = "Resend my award notice"
  }

  sample_utterance {
    utterance = "I need another document"
  }

  sample_utterance {
    utterance = "Please send my paperwork again"
  }

  sample_utterance {
    utterance = "I've lost my letter"
  }

  sample_utterance {
    utterance = "Can you resend my documents"
  }

  dialog_code_hook {
    enabled = false
  }

  fulfillment_code_hook {
    enabled = true
    active  = true

    post_fulfillment_status_specification {
      success_next_step {
        dialog_action {
          type = "EndConversation"
        }
      }

      failure_next_step {
        dialog_action {
          type = "EndConversation"
        }
      }

      timeout_next_step {
        dialog_action {
          type = "EndConversation"
        }
      }
    }
  }

  initial_response_setting {
    next_step {
      dialog_action {
        type = "InvokeDialogCodeHook"
      }
    }

    code_hook {
      enable_code_hook_invocation = true
      active                      = true

      post_code_hook_specification {
        success_next_step {
          dialog_action {
            type           = "ElicitSlot"
            slot_to_elicit = "ReferenceNumber"
          }
        }

        failure_next_step {
          dialog_action {
            type = "EndConversation"
          }
        }

        timeout_next_step {
          dialog_action {
            type = "EndConversation"
          }
        }
      }
    }
  }
}

resource "aws_lexv2models_slot" "request_document_reference_number" {
  bot_id      = aws_lexv2models_bot.contact_centre_ai.id
  bot_version = aws_lexv2models_bot_locale.en_gb.bot_version
  intent_id   = aws_lexv2models_intent.request_document.intent_id
  locale_id   = aws_lexv2models_bot_locale.en_gb.locale_id
  name        = "ReferenceNumber"

  slot_type_id = "AMAZON.AlphaNumeric"

  value_elicitation_setting {
    slot_constraint = "Required"

    prompt_specification {
      max_retries                = 4
      allow_interrupt            = true
      message_selection_strategy = "Random"

      message_group {
        message {
          plain_text_message {
            value = "Please provide your reference number."
          }
        }

        variation {
          plain_text_message {
            value = "What's your reference number?"
          }
        }

        variation {
          plain_text_message {
            value = "Can I have your case reference?"
          }
        }
      }
    }
  }
}

resource "aws_lambda_permission" "lex_development" {
  statement_id  = "lex-lambda-invokeFunction-XVAQFSUUB5-3BEZG3ODQH"
  action        = "lambda:invokeFunction"
  function_name = aws_lambda_function.lex_orchestrator.function_name
  principal     = "lex.amazonaws.com"

  source_account = data.aws_caller_identity.current.account_id

  source_arn = "arn:aws:lex:eu-west-2:533140817207:bot-alias/XVAQFSUUB5/3BEZG3ODQH"
}

resource "aws_connect_contact_flow" "ai_poc_v1" {
  instance_id = "b96ac610-3a3d-41bc-9c84-bac77e4cd0a4"
  name        = "AI_PoC_v1"
  type        = "CONTACT_FLOW"

  content = file("${path.module}/contact_flow.json")
}

resource "aws_connect_hours_of_operation" "basic_hours" {
  instance_id = "b96ac610-3a3d-41bc-9c84-bac77e4cd0a4"
  name        = "Basic Hours"
  description = "Always open hours"
  time_zone   = "America/New_York"

  config {
    day = "MONDAY"

    start_time {
      hours   = 0
      minutes = 0
    }

    end_time {
      hours   = 0
      minutes = 0
    }
  }

  config {
    day = "TUESDAY"

    start_time {
      hours   = 0
      minutes = 0
    }

    end_time {
      hours   = 0
      minutes = 0
    }
  }

  config {
    day = "WEDNESDAY"

    start_time {
      hours   = 0
      minutes = 0
    }

    end_time {
      hours   = 0
      minutes = 0
    }
  }

  config {
    day = "THURSDAY"

    start_time {
      hours   = 0
      minutes = 0
    }

    end_time {
      hours   = 0
      minutes = 0
    }
  }

  config {
    day = "FRIDAY"

    start_time {
      hours   = 0
      minutes = 0
    }

    end_time {
      hours   = 0
      minutes = 0
    }
  }

  config {
    day = "SATURDAY"

    start_time {
      hours   = 0
      minutes = 0
    }

    end_time {
      hours   = 0
      minutes = 0
    }
  }

  config {
    day = "SUNDAY"

    start_time {
      hours   = 0
      minutes = 0
    }

    end_time {
      hours   = 0
      minutes = 0
    }
  }
}

resource "aws_connect_queue" "support" {
  instance_id           = "b96ac610-3a3d-41bc-9c84-bac77e4cd0a4"
  name                  = "Support Queue"
  hours_of_operation_id = aws_connect_hours_of_operation.basic_hours.hours_of_operation_id
}

resource "aws_connect_routing_profile" "basic" {
  instance_id               = "b96ac610-3a3d-41bc-9c84-bac77e4cd0a4"
  name                      = "Basic Routing Profile"
  description               = "A simple routing profile."
  default_outbound_queue_id = "8c892b30-cf75-4328-a19e-177aea840279"

  media_concurrencies {
    channel     = "CHAT"
    concurrency = 2

    cross_channel_behavior {
      behavior_type = "ROUTE_CURRENT_CHANNEL_ONLY"
    }
  }

  media_concurrencies {
    channel     = "TASK"
    concurrency = 1

    cross_channel_behavior {
      behavior_type = "ROUTE_CURRENT_CHANNEL_ONLY"
    }
  }

  media_concurrencies {
    channel     = "VOICE"
    concurrency = 1

    cross_channel_behavior {
      behavior_type = "ROUTE_CURRENT_CHANNEL_ONLY"
    }
  }

  queue_configs {
    queue_id = "729849a2-67ba-4097-9217-6e71ec4c8ee8"
    channel  = "CHAT"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "729849a2-67ba-4097-9217-6e71ec4c8ee8"
    channel  = "TASK"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "729849a2-67ba-4097-9217-6e71ec4c8ee8"
    channel  = "VOICE"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "8c892b30-cf75-4328-a19e-177aea840279"
    channel  = "CHAT"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "8c892b30-cf75-4328-a19e-177aea840279"
    channel  = "TASK"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "8c892b30-cf75-4328-a19e-177aea840279"
    channel  = "VOICE"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "9ecdd4e5-843a-4f6a-8ef5-100c9999e8c8"
    channel  = "CHAT"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "9ecdd4e5-843a-4f6a-8ef5-100c9999e8c8"
    channel  = "TASK"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "9ecdd4e5-843a-4f6a-8ef5-100c9999e8c8"
    channel  = "VOICE"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "d9222b0a-36f0-48ae-b06e-b63082c6c40b"
    channel  = "CHAT"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "d9222b0a-36f0-48ae-b06e-b63082c6c40b"
    channel  = "TASK"
    priority = 1
    delay    = 0
  }

  queue_configs {
    queue_id = "d9222b0a-36f0-48ae-b06e-b63082c6c40b"
    channel  = "VOICE"
    priority = 1
    delay    = 0
  }
}

resource "aws_connect_security_profile" "admin" {
  instance_id = "b96ac610-3a3d-41bc-9c84-bac77e4cd0a4"

  name        = "Admin"
  description = "An administrator can perform all actions available."

  permissions = [
    "AccessMetrics",
    "AccessMetrics.AgentActivityAudit.Access",
    "AccessMetrics.Dashboards.Access",
    "AccessMetrics.DashboardsWithMyData.View",
    "AccessMetrics.HistoricalMetrics.Access",
    "AccessMetrics.RealTimeMetrics.Access",
    "AgentGrouping.Create",
    "AgentGrouping.Edit",
    "AgentGrouping.EnableAndDisable",
    "AgentGrouping.View",
    "AgentStates.Create",
    "AgentStates.Edit",
    "AgentStates.EnableAndDisable",
    "AgentStates.View",
    "AgentTimeCard.View",
    "Analytics.PerformanceMetrics.Access",
    "Audio.View",
    "AudioDeviceSettings.Access",
    "AutomatedVoiceInteraction.Recordings.Redacted.Access",
    "AutomatedVoiceInteraction.Recordings.Redacted.DownloadButton",
    "AutomatedVoiceInteraction.Recordings.Unredacted.Access",
    "AutomatedVoiceInteraction.Recordings.Unredacted.DownloadButton",
    "AutomatedVoiceInteraction.Transcripts.Redacted.Access",
    "AutomatedVoiceInteraction.Transcripts.Unredacted.Access",
    "BasicAgentAccess",
    "Bots.Create",
    "Bots.Edit",
    "Bots.View",
    "CallRecordings.Redacted.Access",
    "CallRecordings.Redacted.DownloadButton",
    "CallRecordings.Unredacted.Access",
    "CallRecordings.Unredacted.DownloadButton",
    "Campaigns.Create",
    "Campaigns.Delete",
    "Campaigns.Edit",
    "Campaigns.Manage",
    "Campaigns.View",
    "Capacity.Edit",
    "Capacity.Publish",
    "Capacity.View",
    "CaseFields.Create",
    "CaseFields.Edit",
    "CaseFields.View",
    "CaseHistory.View",
    "CaseTemplates.Create",
    "CaseTemplates.Edit",
    "CaseTemplates.View",
    "Cases.Create",
    "Cases.Edit",
    "Cases.View",
    "ChatTestMode",
    "CoachingSessions.Create",
    "CoachingSessions.Delete",
    "CoachingSessions.Edit",
    "CoachingSessions.View",
    "Cobrowse.Access",
    "ConfigureContactAttributes.View",
    "ContactAttributes.View",
    "ContactFlowModules.Create",
    "ContactFlowModules.Delete",
    "ContactFlowModules.Edit",
    "ContactFlowModules.Execute",
    "ContactFlowModules.Publish",
    "ContactFlowModules.View",
    "ContactFlows.Create",
    "ContactFlows.Delete",
    "ContactFlows.Edit",
    "ContactFlows.Publish",
    "ContactFlows.View",
    "ContactLensCustomVocabulary.Edit",
    "ContactLensCustomVocabulary.View",
    "ContactLensPostContactSummary.View",
    "ContactSearch.View",
    "ContactSearchQuickViewWidget.Create",
    "ContactSearchQuickViewWidget.Delete",
    "ContactSearchQuickViewWidget.Edit",
    "ContactSearchQuickViewWidget.View",
    "ContactSearchSampleContacts.View",
    "ContactSearchWithCharacteristics.Access",
    "ContactSearchWithCharacteristics.View",
    "ContactSearchWithKeywords.Access",
    "ContactSearchWithKeywords.View",
    "ContactTranscripts.Redacted.Access",
    "ContactTranscripts.Unredacted.Access",
    "ContactTranscripts.Unredacted.DownloadButton",
    "ContentManagement.Create",
    "ContentManagement.Delete",
    "ContentManagement.Edit",
    "ContentManagement.MessageTemplates.Create",
    "ContentManagement.MessageTemplates.Delete",
    "ContentManagement.MessageTemplates.Edit",
    "ContentManagement.MessageTemplates.View",
    "ContentManagement.View",
    "CustomMetrics.Create",
    "CustomMetrics.Delete",
    "CustomMetrics.Edit",
    "CustomMetrics.Publish",
    "CustomMetrics.View",
    "CustomViews.Access",
    "CustomerProfiles.CalculatedAttributes.Create",
    "CustomerProfiles.CalculatedAttributes.Delete",
    "CustomerProfiles.CalculatedAttributes.Edit",
    "CustomerProfiles.CalculatedAttributes.View",
    "CustomerProfiles.Create",
    "CustomerProfiles.Edit",
    "CustomerProfiles.ProfileExplorer.Create",
    "CustomerProfiles.ProfileExplorer.Delete",
    "CustomerProfiles.ProfileExplorer.Edit",
    "CustomerProfiles.ProfileExplorer.View",
    "CustomerProfiles.Segments.Create",
    "CustomerProfiles.Segments.Delete",
    "CustomerProfiles.Segments.Export",
    "CustomerProfiles.Segments.View",
    "CustomerProfiles.View",
    "DataTables.Create",
    "DataTables.Delete",
    "DataTables.Edit",
    "DataTables.EditExpressionValues",
    "DataTables.ManageValues",
    "DataTables.View",
    "DeleteCallRecordings",
    "DownloadCallRecordings",
    "EmailAddresses.Create",
    "EmailAddresses.Edit",
    "EmailAddresses.Remove",
    "EmailAddresses.View",
    "Evaluation.Create",
    "Evaluation.Delete",
    "Evaluation.Edit",
    "Evaluation.View",
    "EvaluationAssistant.Access",
    "EvaluationCalibrationSessions.Create",
    "EvaluationCalibrationSessions.Delete",
    "EvaluationCalibrationSessions.Edit",
    "EvaluationCalibrationSessions.View",
    "EvaluationForms.Create",
    "EvaluationForms.Delete",
    "EvaluationForms.Edit",
    "EvaluationForms.View",
    "EvaluationReviewRequest.Create",
    "EvaluationReviewRequest.Delete",
    "EvaluationReviewRequest.View",
    "EvaluationReviews.Create",
    "EvaluationReviews.View",
    "FileAttachments.Configurations.Edit",
    "FileAttachments.Configurations.View",
    "ForecastScheduleInterval.Edit",
    "ForecastScheduleInterval.View",
    "Forecasting.Edit",
    "Forecasting.Publish",
    "Forecasting.View",
    "GraphTrends.View",
    "HistoricalChanges.View",
    "HoursOfOperation.Create",
    "HoursOfOperation.Delete",
    "HoursOfOperation.Edit",
    "HoursOfOperation.View",
    "ListenCallRecordings",
    "ManagerBargeIn",
    "ManagerListenIn",
    "ManualAssignAnyContact.Enable",
    "ManualAssignMyContacts.Enable",
    "MetricsReports.Create",
    "MetricsReports.Delete",
    "MetricsReports.Edit",
    "MetricsReports.Publish",
    "MetricsReports.Schedule",
    "MetricsReports.Share",
    "MetricsReports.View",
    "MyCoachingSessions.Create",
    "MyCoachingSessions.Delete",
    "MyCoachingSessions.Edit",
    "MyCoachingSessions.View",
    "MyContacts.View",
    "OutboundCallAccess",
    "OutboundEmail.Create",
    "PhoneNumbers.Claim",
    "PhoneNumbers.Edit",
    "PhoneNumbers.Release",
    "PhoneNumbers.View",
    "PredefinedAttributes.Create",
    "PredefinedAttributes.Delete",
    "PredefinedAttributes.Edit",
    "PredefinedAttributes.View",
    "Prompts.Create",
    "Prompts.Delete",
    "Prompts.Edit",
    "Prompts.View",
    "QConnectAIAgents.Create",
    "QConnectAIAgents.Delete",
    "QConnectAIAgents.Edit",
    "QConnectAIAgents.View",
    "QConnectAIPrompts.Create",
    "QConnectAIPrompts.Delete",
    "QConnectAIPrompts.Edit",
    "QConnectAIPrompts.View",
    "QConnectGuardrails.Create",
    "QConnectGuardrails.Delete",
    "QConnectGuardrails.Edit",
    "QConnectGuardrails.View",
    "Queues.Create",
    "Queues.Delete",
    "Queues.Edit",
    "Queues.EditExpressions",
    "Queues.EnableAndDisable",
    "Queues.Purge",
    "Queues.View",
    "RealtimeContactLens.View",
    "RedactedData.View",
    "ReportSchedules.Create",
    "ReportSchedules.Delete",
    "ReportSchedules.Edit",
    "ReportSchedules.View",
    "ReportsAdmin.Access",
    "ReportsAdmin.Delete",
    "ReportsAdmin.Publish",
    "ReportsAdmin.Schedule",
    "ReportsAdmin.View",
    "RoutingPolicies.Create",
    "RoutingPolicies.Delete",
    "RoutingPolicies.Edit",
    "RoutingPolicies.View",
    "Rules.Create",
    "Rules.Delete",
    "Rules.Edit",
    "Rules.View",
    "RulesGenerativeAI.Create",
    "RulesGenerativeAI.Delete",
    "RulesGenerativeAI.Edit",
    "RulesGenerativeAI.View",
    "Scheduling.Edit",
    "Scheduling.Publish",
    "Scheduling.View",
    "ScreenRecording.Access",
    "ScreenRecording.Delete",
    "ScreenRecording.Download",
    "SecurityProfiles.Create",
    "SecurityProfiles.Delete",
    "SecurityProfiles.Edit",
    "SecurityProfiles.View",
    "SelfAssignContacts.Access",
    "StaffCalendar.Edit",
    "StaffCalendar.View",
    "StopContact.Enabled",
    "TaskTemplates.Create",
    "TaskTemplates.Delete",
    "TaskTemplates.Edit",
    "TaskTemplates.View",
    "TeamCalendar.Edit",
    "TeamCalendar.View",
    "TestCases.Create",
    "TestCases.Delete",
    "TestCases.Edit",
    "TestCases.Execute",
    "TestCases.Publish",
    "TestCases.View",
    "TimeOff.Approve",
    "TimeOff.Edit",
    "TimeOff.View",
    "TimeOffBalance.Edit",
    "TimeOffBalance.View",
    "Transcript.View",
    "TransferContact.Enabled",
    "TransferDestinations.Create",
    "TransferDestinations.Delete",
    "TransferDestinations.Edit",
    "TransferDestinations.View",
    "UnredactedData.View",
    "UpdateContactSchedule.Enabled",
    "Users.Create",
    "Users.Delete",
    "Users.Edit",
    "Users.EditPermission",
    "Users.EnableAndDisable",
    "Users.View",
    "VideoContact.Access",
    "Views.Create",
    "Views.Edit",
    "Views.Remove",
    "Views.View",
    "VoiceId.Access",
    "VoiceIdAttributesAndSearch.View",
    "VoiceIdUpdateSpeakerId.Access",
    "Wisdom.View",
    "Workspaces.Assign",
    "Workspaces.Create",
    "Workspaces.Delete",
    "Workspaces.Edit",
    "Workspaces.EditVisibility",
    "Workspaces.View"
  ]
}