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