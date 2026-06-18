export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      admin_users: {
        Row: {
          created_at: string
          email: string
          id: string
          name: string | null
          role: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          email: string
          id: string
          name?: string | null
          role?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          name?: string | null
          role?: string
          updated_at?: string
        }
        Relationships: []
      }
      agent_configs: {
        Row: {
          allowed_tools: string[] | null
          buffer_debounce_ms: number
          created_at: string
          created_by: string | null
          frequency_penalty: number | null
          helicone_cache: boolean
          id: string
          llm_timeout_ms: number
          max_tokens: number
          max_tool_iterations: number
          model: string
          name: string
          notes: string | null
          presence_penalty: number | null
          prompt_image: string | null
          rollout_percent: number
          stage: Database["public"]["Enums"]["agent_stage"]
          status: Database["public"]["Enums"]["config_status"]
          streaming: boolean
          stt_timeout_ms: number
          temperature: number
          top_p: number | null
          updated_at: string
          version: string
          vision_timeout_ms: number
          wait_seconds: number
        }
        Insert: {
          allowed_tools?: string[] | null
          buffer_debounce_ms?: number
          created_at?: string
          created_by?: string | null
          frequency_penalty?: number | null
          helicone_cache?: boolean
          id?: string
          llm_timeout_ms?: number
          max_tokens: number
          max_tool_iterations?: number
          model: string
          name: string
          notes?: string | null
          presence_penalty?: number | null
          prompt_image?: string | null
          rollout_percent?: number
          stage: Database["public"]["Enums"]["agent_stage"]
          status?: Database["public"]["Enums"]["config_status"]
          streaming?: boolean
          stt_timeout_ms?: number
          temperature: number
          top_p?: number | null
          updated_at?: string
          version: string
          vision_timeout_ms?: number
          wait_seconds?: number
        }
        Update: {
          allowed_tools?: string[] | null
          buffer_debounce_ms?: number
          created_at?: string
          created_by?: string | null
          frequency_penalty?: number | null
          helicone_cache?: boolean
          id?: string
          llm_timeout_ms?: number
          max_tokens?: number
          max_tool_iterations?: number
          model?: string
          name?: string
          notes?: string | null
          presence_penalty?: number | null
          prompt_image?: string | null
          rollout_percent?: number
          stage?: Database["public"]["Enums"]["agent_stage"]
          status?: Database["public"]["Enums"]["config_status"]
          streaming?: boolean
          stt_timeout_ms?: number
          temperature?: number
          top_p?: number | null
          updated_at?: string
          version?: string
          vision_timeout_ms?: number
          wait_seconds?: number
        }
        Relationships: []
      }
      agent_configs_versions: {
        Row: {
          change_reason: string | null
          changed_at: string
          changed_by: string | null
          config_id: string
          id: string
          snapshot: Json
          version_num: number
        }
        Insert: {
          change_reason?: string | null
          changed_at?: string
          changed_by?: string | null
          config_id: string
          id?: string
          snapshot: Json
          version_num: number
        }
        Update: {
          change_reason?: string | null
          changed_at?: string
          changed_by?: string | null
          config_id?: string
          id?: string
          snapshot?: Json
          version_num?: number
        }
        Relationships: [
          {
            foreignKeyName: "agent_configs_versions_config_id_fkey"
            columns: ["config_id"]
            isOneToOne: false
            referencedRelation: "agent_configs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agent_configs_versions_config_id_fkey"
            columns: ["config_id"]
            isOneToOne: false
            referencedRelation: "v_active_prompts"
            referencedColumns: ["config_id"]
          },
        ]
      }
      agent_rules: {
        Row: {
          content: string
          content_tsv: unknown
          created_at: string
          created_by: string | null
          display_order: number
          id: string
          language: string
          slug: string
          status: Database["public"]["Enums"]["config_status"]
          tipo: Database["public"]["Enums"]["rule_tipo"]
          token_estimate: number | null
          topic: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          content: string
          content_tsv?: unknown
          created_at?: string
          created_by?: string | null
          display_order?: number
          id?: string
          language?: string
          slug: string
          status?: Database["public"]["Enums"]["config_status"]
          tipo: Database["public"]["Enums"]["rule_tipo"]
          token_estimate?: number | null
          topic: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          content?: string
          content_tsv?: unknown
          created_at?: string
          created_by?: string | null
          display_order?: number
          id?: string
          language?: string
          slug?: string
          status?: Database["public"]["Enums"]["config_status"]
          tipo?: Database["public"]["Enums"]["rule_tipo"]
          token_estimate?: number | null
          topic?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      agent_rules_versions: {
        Row: {
          change_reason: string | null
          changed_at: string
          changed_by: string | null
          content: string
          id: string
          rule_id: string
          status: Database["public"]["Enums"]["config_status"]
          tipo: Database["public"]["Enums"]["rule_tipo"]
          topic: string
          version_num: number
        }
        Insert: {
          change_reason?: string | null
          changed_at?: string
          changed_by?: string | null
          content: string
          id?: string
          rule_id: string
          status: Database["public"]["Enums"]["config_status"]
          tipo: Database["public"]["Enums"]["rule_tipo"]
          topic: string
          version_num: number
        }
        Update: {
          change_reason?: string | null
          changed_at?: string
          changed_by?: string | null
          content?: string
          id?: string
          rule_id?: string
          status?: Database["public"]["Enums"]["config_status"]
          tipo?: Database["public"]["Enums"]["rule_tipo"]
          topic?: string
          version_num?: number
        }
        Relationships: [
          {
            foreignKeyName: "agent_rules_versions_rule_id_fkey"
            columns: ["rule_id"]
            isOneToOne: false
            referencedRelation: "agent_rules"
            referencedColumns: ["id"]
          },
        ]
      }
      attention_dismissals: {
        Row: {
          dismissed_at: string
          dismissed_by: string | null
          dismissed_by_email: string | null
          dismissed_until: string | null
          id: string
          kind: string
          reason: string | null
          user_id: string
        }
        Insert: {
          dismissed_at?: string
          dismissed_by?: string | null
          dismissed_by_email?: string | null
          dismissed_until?: string | null
          id?: string
          kind: string
          reason?: string | null
          user_id: string
        }
        Update: {
          dismissed_at?: string
          dismissed_by?: string | null
          dismissed_by_email?: string | null
          dismissed_until?: string | null
          id?: string
          kind?: string
          reason?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "attention_dismissals_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor_email: string | null
          actor_id: string | null
          after: Json | null
          before: Json | null
          created_at: string
          entity: string
          entity_id: string | null
          id: string
          ip_address: string | null
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_email?: string | null
          actor_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          entity: string
          entity_id?: string | null
          id?: string
          ip_address?: string | null
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_email?: string | null
          actor_id?: string | null
          after?: Json | null
          before?: Json | null
          created_at?: string
          entity?: string
          entity_id?: string | null
          id?: string
          ip_address?: string | null
          user_agent?: string | null
        }
        Relationships: []
      }
      daily_snapshots: {
        Row: {
          calories_consumed: number
          calories_target: number | null
          carbs_g: number
          closed_at: string | null
          created_at: string
          current_protocol: Database["public"]["Enums"]["protocol_enum"] | null
          daily_balance: number | null
          date: string
          day_closed: boolean
          day_status: string
          deficit_accumulated: number
          exercise_calories: number
          fat_g: number
          gap_reminder_sent_at: string | null
          id: string
          protein_g: number
          protein_target: number | null
          sleep_hours: number | null
          steps: number | null
          training_done: boolean
          updated_at: string
          user_id: string
          water_consumed_ml: number
          xp_earned: number
        }
        Insert: {
          calories_consumed?: number
          calories_target?: number | null
          carbs_g?: number
          closed_at?: string | null
          created_at?: string
          current_protocol?: Database["public"]["Enums"]["protocol_enum"] | null
          daily_balance?: number | null
          date: string
          day_closed?: boolean
          day_status?: string
          deficit_accumulated?: number
          exercise_calories?: number
          fat_g?: number
          gap_reminder_sent_at?: string | null
          id?: string
          protein_g?: number
          protein_target?: number | null
          sleep_hours?: number | null
          steps?: number | null
          training_done?: boolean
          updated_at?: string
          user_id: string
          water_consumed_ml?: number
          xp_earned?: number
        }
        Update: {
          calories_consumed?: number
          calories_target?: number | null
          carbs_g?: number
          closed_at?: string | null
          created_at?: string
          current_protocol?: Database["public"]["Enums"]["protocol_enum"] | null
          daily_balance?: number | null
          date?: string
          day_closed?: boolean
          day_status?: string
          deficit_accumulated?: number
          exercise_calories?: number
          fat_g?: number
          gap_reminder_sent_at?: string | null
          id?: string
          protein_g?: number
          protein_target?: number | null
          sleep_hours?: number | null
          steps?: number | null
          training_done?: boolean
          updated_at?: string
          user_id?: string
          water_consumed_ml?: number
          xp_earned?: number
        }
        Relationships: [
          {
            foreignKeyName: "daily_snapshots_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      engagement_phrases: {
        Row: {
          active: boolean
          created_at: string
          curated_by: string | null
          id: string
          language: string
          last_used_at: string | null
          phrase: string
          picked_count: number
          slot: string
          used_count: number
        }
        Insert: {
          active?: boolean
          created_at?: string
          curated_by?: string | null
          id?: string
          language?: string
          last_used_at?: string | null
          phrase: string
          picked_count?: number
          slot?: string
          used_count?: number
        }
        Update: {
          active?: boolean
          created_at?: string
          curated_by?: string | null
          id?: string
          language?: string
          last_used_at?: string | null
          phrase?: string
          picked_count?: number
          slot?: string
          used_count?: number
        }
        Relationships: []
      }
      feature_flags: {
        Row: {
          description: string | null
          key: string
          rollout_percent: number
          updated_at: string
          user_allowlist: string[]
          user_blocklist: string[]
          value: Json
        }
        Insert: {
          description?: string | null
          key: string
          rollout_percent?: number
          updated_at?: string
          user_allowlist?: string[]
          user_blocklist?: string[]
          value: Json
        }
        Update: {
          description?: string | null
          key?: string
          rollout_percent?: number
          updated_at?: string
          user_allowlist?: string[]
          user_blocklist?: string[]
          value?: Json
        }
        Relationships: []
      }
      food_db: {
        Row: {
          carbs_g: number | null
          category: string | null
          country_code: string
          embedding: string | null
          fat_g: number | null
          fiber_g: number | null
          id: number
          kcal_per_100g: number | null
          name_norm: string | null
          name_pt: string
          protein_g: number | null
          source: string
        }
        Insert: {
          carbs_g?: number | null
          category?: string | null
          country_code?: string
          embedding?: string | null
          fat_g?: number | null
          fiber_g?: number | null
          id?: number
          kcal_per_100g?: number | null
          name_norm?: string | null
          name_pt: string
          protein_g?: number | null
          source?: string
        }
        Update: {
          carbs_g?: number | null
          category?: string | null
          country_code?: string
          embedding?: string | null
          fat_g?: number | null
          fiber_g?: number | null
          id?: number
          kcal_per_100g?: number | null
          name_norm?: string | null
          name_pt?: string
          protein_g?: number | null
          source?: string
        }
        Relationships: []
      }
      food_education_phrases: {
        Row: {
          active: boolean
          bloco_id: string | null
          created_at: string
          curated_by: string | null
          food_canonical_name: string
          food_name_embedding: string | null
          id: string
          language: string | null
          last_used_at: string | null
          phrase: string
          polaridade: string | null
          tags: Json | null
          usage_count: number
        }
        Insert: {
          active?: boolean
          bloco_id?: string | null
          created_at?: string
          curated_by?: string | null
          food_canonical_name: string
          food_name_embedding?: string | null
          id?: string
          language?: string | null
          last_used_at?: string | null
          phrase: string
          polaridade?: string | null
          tags?: Json | null
          usage_count?: number
        }
        Update: {
          active?: boolean
          bloco_id?: string | null
          created_at?: string
          curated_by?: string | null
          food_canonical_name?: string
          food_name_embedding?: string | null
          id?: string
          language?: string | null
          last_used_at?: string | null
          phrase?: string
          polaridade?: string | null
          tags?: Json | null
          usage_count?: number
        }
        Relationships: []
      }
      global_config: {
        Row: {
          description: string | null
          key: string
          updated_at: string
          updated_by: string | null
          value: Json
        }
        Insert: {
          description?: string | null
          key: string
          updated_at?: string
          updated_by?: string | null
          value: Json
        }
        Update: {
          description?: string | null
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Relationships: []
      }
      llm_evaluations: {
        Row: {
          agent_name: string | null
          evaluated_at: string
          expected_response: string | null
          id: string
          message_id: string | null
          model_used: string | null
          reasoning: string | null
          response_obtained: string | null
          score: number | null
          user_id: string | null
          user_input: string | null
        }
        Insert: {
          agent_name?: string | null
          evaluated_at?: string
          expected_response?: string | null
          id?: string
          message_id?: string | null
          model_used?: string | null
          reasoning?: string | null
          response_obtained?: string | null
          score?: number | null
          user_id?: string | null
          user_input?: string | null
        }
        Update: {
          agent_name?: string | null
          evaluated_at?: string
          expected_response?: string | null
          id?: string
          message_id?: string | null
          model_used?: string | null
          reasoning?: string | null
          response_obtained?: string | null
          score?: number | null
          user_id?: string | null
          user_input?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "llm_evaluations_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "llm_evaluations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      meal_logs: {
        Row: {
          carbs_g: number | null
          confidence: number | null
          consumed_at: string
          created_at: string
          fat_g: number | null
          food_name: string
          id: string
          image_url: string | null
          kcal: number | null
          meal_type: Database["public"]["Enums"]["meal_type_enum"] | null
          protein_g: number | null
          quantity_g: number | null
          raw_message_id: string | null
          raw_provider_message_id: string | null
          snapshot_id: string | null
          source: string | null
          user_id: string
        }
        Insert: {
          carbs_g?: number | null
          confidence?: number | null
          consumed_at?: string
          created_at?: string
          fat_g?: number | null
          food_name: string
          id?: string
          image_url?: string | null
          kcal?: number | null
          meal_type?: Database["public"]["Enums"]["meal_type_enum"] | null
          protein_g?: number | null
          quantity_g?: number | null
          raw_message_id?: string | null
          raw_provider_message_id?: string | null
          snapshot_id?: string | null
          source?: string | null
          user_id: string
        }
        Update: {
          carbs_g?: number | null
          confidence?: number | null
          consumed_at?: string
          created_at?: string
          fat_g?: number | null
          food_name?: string
          id?: string
          image_url?: string | null
          kcal?: number | null
          meal_type?: Database["public"]["Enums"]["meal_type_enum"] | null
          protein_g?: number | null
          quantity_g?: number | null
          raw_message_id?: string | null
          raw_provider_message_id?: string | null
          snapshot_id?: string | null
          source?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "meal_logs_snapshot_id_fkey"
            columns: ["snapshot_id"]
            isOneToOne: false
            referencedRelation: "daily_snapshots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meal_logs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      message_buffer: {
        Row: {
          buffered_at: string
          flush_after: string
          messages: Json
          user_id: string
        }
        Insert: {
          buffered_at?: string
          flush_after: string
          messages?: Json
          user_id: string
        }
        Update: {
          buffered_at?: string
          flush_after?: string
          messages?: Json
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_buffer_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      message_embeddings: {
        Row: {
          created_at: string
          embedding: string | null
          message_id: string
        }
        Insert: {
          created_at?: string
          embedding?: string | null
          message_id: string
        }
        Update: {
          created_at?: string
          embedding?: string | null
          message_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_embeddings_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: true
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          agent_stage: string | null
          completion_tokens: number | null
          content: string | null
          content_type: Database["public"]["Enums"]["content_type_enum"]
          cost_usd: number | null
          created_at: string
          delivery_error: Json | null
          delivery_status: string | null
          direction: Database["public"]["Enums"]["direction_enum"]
          id: string
          intent: string | null
          latency_ms: number | null
          media_storage_path: string | null
          media_url: string | null
          model_used: string | null
          prompt_tokens: number | null
          provider: string
          provider_message_id: string | null
          raw_payload: Json | null
          review_flag: Database["public"]["Enums"]["review_flag_enum"] | null
          review_flagged_at: string | null
          review_flagged_by: string | null
          review_note: string | null
          role: Database["public"]["Enums"]["msg_role_enum"]
          user_id: string
        }
        Insert: {
          agent_stage?: string | null
          completion_tokens?: number | null
          content?: string | null
          content_type: Database["public"]["Enums"]["content_type_enum"]
          cost_usd?: number | null
          created_at?: string
          delivery_error?: Json | null
          delivery_status?: string | null
          direction: Database["public"]["Enums"]["direction_enum"]
          id?: string
          intent?: string | null
          latency_ms?: number | null
          media_storage_path?: string | null
          media_url?: string | null
          model_used?: string | null
          prompt_tokens?: number | null
          provider?: string
          provider_message_id?: string | null
          raw_payload?: Json | null
          review_flag?: Database["public"]["Enums"]["review_flag_enum"] | null
          review_flagged_at?: string | null
          review_flagged_by?: string | null
          review_note?: string | null
          role: Database["public"]["Enums"]["msg_role_enum"]
          user_id: string
        }
        Update: {
          agent_stage?: string | null
          completion_tokens?: number | null
          content?: string | null
          content_type?: Database["public"]["Enums"]["content_type_enum"]
          cost_usd?: number | null
          created_at?: string
          delivery_error?: Json | null
          delivery_status?: string | null
          direction?: Database["public"]["Enums"]["direction_enum"]
          id?: string
          intent?: string | null
          latency_ms?: number | null
          media_storage_path?: string | null
          media_url?: string | null
          model_used?: string | null
          prompt_tokens?: number | null
          provider?: string
          provider_message_id?: string | null
          raw_payload?: Json | null
          review_flag?: Database["public"]["Enums"]["review_flag_enum"] | null
          review_flagged_at?: string | null
          review_flagged_by?: string | null
          review_note?: string | null
          role?: Database["public"]["Enums"]["msg_role_enum"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_review_flagged_by_fkey"
            columns: ["review_flagged_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      method_chunks: {
        Row: {
          chunk_index: number
          content: string
          created_at: string
          embedding: string | null
          id: string
          page_title: string
          protocol: string | null
        }
        Insert: {
          chunk_index?: number
          content: string
          created_at?: string
          embedding?: string | null
          id?: string
          page_title: string
          protocol?: string | null
        }
        Update: {
          chunk_index?: number
          content?: string
          created_at?: string
          embedding?: string | null
          id?: string
          page_title?: string
          protocol?: string | null
        }
        Relationships: []
      }
      pending_approvals: {
        Row: {
          application_error: string | null
          application_result: Json | null
          confidence: string | null
          created_at: string | null
          decided_at: string | null
          decided_via: string | null
          id: string
          payload: Json
          reason: string | null
          run_id: string | null
          status: string
          telegram_chat_id: string | null
          telegram_message_id: number | null
          type: string
        }
        Insert: {
          application_error?: string | null
          application_result?: Json | null
          confidence?: string | null
          created_at?: string | null
          decided_at?: string | null
          decided_via?: string | null
          id?: string
          payload: Json
          reason?: string | null
          run_id?: string | null
          status?: string
          telegram_chat_id?: string | null
          telegram_message_id?: number | null
          type: string
        }
        Update: {
          application_error?: string | null
          application_result?: Json | null
          confidence?: string | null
          created_at?: string | null
          decided_at?: string | null
          decided_via?: string | null
          id?: string
          payload?: Json
          reason?: string | null
          run_id?: string | null
          status?: string
          telegram_chat_id?: string | null
          telegram_message_id?: number | null
          type?: string
        }
        Relationships: []
      }
      pending_registrations: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          proposal: Json
          proposal_msg_id: string | null
          resolved_at: string | null
          status: Database["public"]["Enums"]["pending_registration_status"]
          user_id: string
        }
        Insert: {
          created_at?: string
          expires_at: string
          id?: string
          proposal: Json
          proposal_msg_id?: string | null
          resolved_at?: string | null
          status?: Database["public"]["Enums"]["pending_registration_status"]
          user_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          proposal?: Json
          proposal_msg_id?: string | null
          resolved_at?: string | null
          status?: Database["public"]["Enums"]["pending_registration_status"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pending_registrations_proposal_msg_id_fkey"
            columns: ["proposal_msg_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pending_registrations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      prescriptions: {
        Row: {
          created_at: string
          generated_at: string
          generated_by: string | null
          id: string
          last_sent_at: string | null
          notes: string | null
          payload: Json
          type: string
          user_id: string
          valid_until: string | null
          version: number | null
        }
        Insert: {
          created_at?: string
          generated_at?: string
          generated_by?: string | null
          id?: string
          last_sent_at?: string | null
          notes?: string | null
          payload: Json
          type: string
          user_id: string
          valid_until?: string | null
          version?: number | null
        }
        Update: {
          created_at?: string
          generated_at?: string
          generated_by?: string | null
          id?: string
          last_sent_at?: string | null
          notes?: string | null
          payload?: Json
          type?: string
          user_id?: string
          valid_until?: string | null
          version?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "prescriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      processed_messages: {
        Row: {
          processed_at: string
          provider_message_id: string
        }
        Insert: {
          processed_at?: string
          provider_message_id: string
        }
        Update: {
          processed_at?: string
          provider_message_id?: string
        }
        Relationships: []
      }
      product_events: {
        Row: {
          event: string
          id: string
          occurred_at: string
          properties: Json | null
          user_id: string | null
        }
        Insert: {
          event: string
          id?: string
          occurred_at?: string
          properties?: Json | null
          user_id?: string | null
        }
        Update: {
          event?: string
          id?: string
          occurred_at?: string
          properties?: Json | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "product_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      prompt_backups: {
        Row: {
          backed_up_at: string
          char_count: number | null
          id: string
          label: string | null
          stage: string
          system_prompt: string
        }
        Insert: {
          backed_up_at?: string
          char_count?: number | null
          id?: string
          label?: string | null
          stage: string
          system_prompt: string
        }
        Update: {
          backed_up_at?: string
          char_count?: number | null
          id?: string
          label?: string | null
          stage?: string
          system_prompt?: string
        }
        Relationships: []
      }
      reevaluations: {
        Row: {
          agent_decision: Json | null
          bf_percent: number | null
          created_at: string
          evaluation_date: string
          id: string
          photos: string[] | null
          user_feedback: string | null
          user_id: string
          weight_kg: number | null
        }
        Insert: {
          agent_decision?: Json | null
          bf_percent?: number | null
          created_at?: string
          evaluation_date: string
          id?: string
          photos?: string[] | null
          user_feedback?: string | null
          user_id: string
          weight_kg?: number | null
        }
        Update: {
          agent_decision?: Json | null
          bf_percent?: number | null
          created_at?: string
          evaluation_date?: string
          id?: string
          photos?: string[] | null
          user_feedback?: string | null
          user_id?: string
          weight_kg?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "reevaluations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      service_credentials: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          key_name: string
          last_test_result: string | null
          last_tested_at: string | null
          notes: string | null
          service: string
          updated_at: string
          updated_by: string | null
          value: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          key_name: string
          last_test_result?: string | null
          last_tested_at?: string | null
          notes?: string | null
          service: string
          updated_at?: string
          updated_by?: string | null
          value: string
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          key_name?: string
          last_test_result?: string | null
          last_tested_at?: string | null
          notes?: string | null
          service?: string
          updated_at?: string
          updated_by?: string | null
          value?: string
        }
        Relationships: []
      }
      subscription_events: {
        Row: {
          amount_cents: number | null
          created_at: string
          currency: string
          event_type: string
          id: string
          payload: Json | null
          provider_event_id: string | null
          subscription_id: string | null
          user_id: string | null
        }
        Insert: {
          amount_cents?: number | null
          created_at?: string
          currency?: string
          event_type: string
          id?: string
          payload?: Json | null
          provider_event_id?: string | null
          subscription_id?: string | null
          user_id?: string | null
        }
        Update: {
          amount_cents?: number | null
          created_at?: string
          currency?: string
          event_type?: string
          id?: string
          payload?: Json | null
          provider_event_id?: string | null
          subscription_id?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "subscription_events_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscription_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      subscriptions: {
        Row: {
          cancel_at_period_end: boolean
          created_at: string
          current_period_end: string | null
          current_period_start: string | null
          id: string
          metadata: Json | null
          plan: Database["public"]["Enums"]["plan_enum"]
          provider: string
          provider_subscription_id: string | null
          status: Database["public"]["Enums"]["sub_status"]
          trial_ends_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          cancel_at_period_end?: boolean
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          id?: string
          metadata?: Json | null
          plan: Database["public"]["Enums"]["plan_enum"]
          provider?: string
          provider_subscription_id?: string | null
          status: Database["public"]["Enums"]["sub_status"]
          trial_ends_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          cancel_at_period_end?: boolean
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          id?: string
          metadata?: Json | null
          plan?: Database["public"]["Enums"]["plan_enum"]
          provider?: string
          provider_subscription_id?: string | null
          status?: Database["public"]["Enums"]["sub_status"]
          trial_ends_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      tools_audit: {
        Row: {
          arguments: Json | null
          created_at: string
          duration_ms: number | null
          error: string | null
          id: string
          message_id: string | null
          result: Json | null
          success: boolean
          tool_name: string
          user_id: string | null
        }
        Insert: {
          arguments?: Json | null
          created_at?: string
          duration_ms?: number | null
          error?: string | null
          id?: string
          message_id?: string | null
          result?: Json | null
          success: boolean
          tool_name: string
          user_id?: string | null
        }
        Update: {
          arguments?: Json | null
          created_at?: string
          duration_ms?: number | null
          error?: string | null
          id?: string
          message_id?: string | null
          result?: Json | null
          success?: boolean
          tool_name?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tools_audit_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tools_audit_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      training_plans: {
        Row: {
          active: boolean
          created_at: string
          days_per_week: number
          equipment_summary: string | null
          generated_at: string
          generated_by: string | null
          id: string
          notes: string | null
          plan_type: string
          user_id: string
          valid_until: string | null
          version: number | null
          weekly_schedule: Json
        }
        Insert: {
          active?: boolean
          created_at?: string
          days_per_week: number
          equipment_summary?: string | null
          generated_at?: string
          generated_by?: string | null
          id?: string
          notes?: string | null
          plan_type?: string
          user_id: string
          valid_until?: string | null
          version?: number | null
          weekly_schedule: Json
        }
        Update: {
          active?: boolean
          created_at?: string
          days_per_week?: number
          equipment_summary?: string | null
          generated_at?: string
          generated_by?: string | null
          id?: string
          notes?: string | null
          plan_type?: string
          user_id?: string
          valid_until?: string | null
          version?: number | null
          weekly_schedule?: Json
        }
        Relationships: [
          {
            foreignKeyName: "training_plans_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      tts_cache: {
        Row: {
          audio_path: string
          created_at: string
          hits: number
          last_used_at: string
          provider: string
          text_hash: string
          text_preview: string | null
          voice_id: string
        }
        Insert: {
          audio_path: string
          created_at?: string
          hits?: number
          last_used_at?: string
          provider: string
          text_hash: string
          text_preview?: string | null
          voice_id: string
        }
        Update: {
          audio_path?: string
          created_at?: string
          hits?: number
          last_used_at?: string
          provider?: string
          text_hash?: string
          text_preview?: string | null
          voice_id?: string
        }
        Relationships: []
      }
      user_food_corrections: {
        Row: {
          confirmed_count: number
          contradicted_count: number
          corrected_to: string
          custom_carbs_g: number | null
          custom_fat_g: number | null
          custom_kcal_per_100g: number | null
          custom_protein_g: number | null
          first_seen: string
          id: string
          last_seen: string
          said_name: string
          status: string
          user_id: string
        }
        Insert: {
          confirmed_count?: number
          contradicted_count?: number
          corrected_to: string
          custom_carbs_g?: number | null
          custom_fat_g?: number | null
          custom_kcal_per_100g?: number | null
          custom_protein_g?: number | null
          first_seen?: string
          id?: string
          last_seen?: string
          said_name: string
          status?: string
          user_id: string
        }
        Update: {
          confirmed_count?: number
          contradicted_count?: number
          corrected_to?: string
          custom_carbs_g?: number | null
          custom_fat_g?: number | null
          custom_kcal_per_100g?: number | null
          custom_protein_g?: number | null
          first_seen?: string
          id?: string
          last_seen?: string
          said_name?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_food_corrections_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_phrase_cooldown: {
        Row: {
          last_seen_at: string
          phrase_id: string
          phrase_table: string
          user_id: string
        }
        Insert: {
          last_seen_at?: string
          phrase_id: string
          phrase_table: string
          user_id: string
        }
        Update: {
          last_seen_at?: string
          phrase_id?: string
          phrase_table?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_phrase_cooldown_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_profiles: {
        Row: {
          activity_level: Database["public"]["Enums"]["activity_enum"] | null
          bedtime: string | null
          bf_estimated_at: string | null
          bf_percent_estimated: number | null
          bf_source: string | null
          birth_date: string | null
          body_fat_measured_at: string | null
          body_fat_percent: number | null
          created_at: string
          current_protocol: Database["public"]["Enums"]["protocol_enum"] | null
          cycle_start_at: string | null
          cycle_start_bf_percent: number | null
          cycle_start_training_freq: number | null
          cycle_start_weight_kg: number | null
          deficit_level: number | null
          food_organization: string | null
          goal_type: Database["public"]["Enums"]["goal_type_enum"] | null
          goal_value: number | null
          height_cm: number | null
          hunger_level: Database["public"]["Enums"]["hunger_enum"] | null
          onboarding_completed: boolean
          onboarding_step: number
          sex: Database["public"]["Enums"]["sex_enum"] | null
          training_frequency: number | null
          updated_at: string
          user_id: string
          wake_time: string | null
          water_intake: Database["public"]["Enums"]["water_enum"] | null
          weight_kg: number | null
        }
        Insert: {
          activity_level?: Database["public"]["Enums"]["activity_enum"] | null
          bedtime?: string | null
          bf_estimated_at?: string | null
          bf_percent_estimated?: number | null
          bf_source?: string | null
          birth_date?: string | null
          body_fat_measured_at?: string | null
          body_fat_percent?: number | null
          created_at?: string
          current_protocol?: Database["public"]["Enums"]["protocol_enum"] | null
          cycle_start_at?: string | null
          cycle_start_bf_percent?: number | null
          cycle_start_training_freq?: number | null
          cycle_start_weight_kg?: number | null
          deficit_level?: number | null
          food_organization?: string | null
          goal_type?: Database["public"]["Enums"]["goal_type_enum"] | null
          goal_value?: number | null
          height_cm?: number | null
          hunger_level?: Database["public"]["Enums"]["hunger_enum"] | null
          onboarding_completed?: boolean
          onboarding_step?: number
          sex?: Database["public"]["Enums"]["sex_enum"] | null
          training_frequency?: number | null
          updated_at?: string
          user_id: string
          wake_time?: string | null
          water_intake?: Database["public"]["Enums"]["water_enum"] | null
          weight_kg?: number | null
        }
        Update: {
          activity_level?: Database["public"]["Enums"]["activity_enum"] | null
          bedtime?: string | null
          bf_estimated_at?: string | null
          bf_percent_estimated?: number | null
          bf_source?: string | null
          birth_date?: string | null
          body_fat_measured_at?: string | null
          body_fat_percent?: number | null
          created_at?: string
          current_protocol?: Database["public"]["Enums"]["protocol_enum"] | null
          cycle_start_at?: string | null
          cycle_start_bf_percent?: number | null
          cycle_start_training_freq?: number | null
          cycle_start_weight_kg?: number | null
          deficit_level?: number | null
          food_organization?: string | null
          goal_type?: Database["public"]["Enums"]["goal_type_enum"] | null
          goal_value?: number | null
          height_cm?: number | null
          hunger_level?: Database["public"]["Enums"]["hunger_enum"] | null
          onboarding_completed?: boolean
          onboarding_step?: number
          sex?: Database["public"]["Enums"]["sex_enum"] | null
          training_frequency?: number | null
          updated_at?: string
          user_id?: string
          wake_time?: string | null
          water_intake?: Database["public"]["Enums"]["water_enum"] | null
          weight_kg?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "user_profiles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_progress: {
        Row: {
          badges_earned: string[]
          blocks_completed: number
          current_bf_percent: number | null
          current_streak: number
          current_weight: number | null
          deficit_block: number
          last_active_date: string | null
          level: number
          longest_streak: number
          next_reevaluation: string | null
          updated_at: string
          user_id: string
          xp_total: number
        }
        Insert: {
          badges_earned?: string[]
          blocks_completed?: number
          current_bf_percent?: number | null
          current_streak?: number
          current_weight?: number | null
          deficit_block?: number
          last_active_date?: string | null
          level?: number
          longest_streak?: number
          next_reevaluation?: string | null
          updated_at?: string
          user_id: string
          xp_total?: number
        }
        Update: {
          badges_earned?: string[]
          blocks_completed?: number
          current_bf_percent?: number | null
          current_streak?: number
          current_weight?: number | null
          deficit_block?: number
          last_active_date?: string | null
          level?: number
          longest_streak?: number
          next_reevaluation?: string | null
          updated_at?: string
          user_id?: string
          xp_total?: number
        }
        Relationships: [
          {
            foreignKeyName: "user_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      users: {
        Row: {
          admin_notes: string | null
          country: string | null
          country_confirmed: boolean
          country_detected_from_wpp: string | null
          created_at: string
          email: string | null
          id: string
          last_active_at: string | null
          locale: string | null
          metadata: Json
          name: string | null
          status: Database["public"]["Enums"]["user_status"]
          summary: string | null
          summary_updated_at: string | null
          tags: string[]
          timezone: string | null
          updated_at: string
          wpp: string
        }
        Insert: {
          admin_notes?: string | null
          country?: string | null
          country_confirmed?: boolean
          country_detected_from_wpp?: string | null
          created_at?: string
          email?: string | null
          id?: string
          last_active_at?: string | null
          locale?: string | null
          metadata?: Json
          name?: string | null
          status?: Database["public"]["Enums"]["user_status"]
          summary?: string | null
          summary_updated_at?: string | null
          tags?: string[]
          timezone?: string | null
          updated_at?: string
          wpp: string
        }
        Update: {
          admin_notes?: string | null
          country?: string | null
          country_confirmed?: boolean
          country_detected_from_wpp?: string | null
          created_at?: string
          email?: string | null
          id?: string
          last_active_at?: string | null
          locale?: string | null
          metadata?: Json
          name?: string | null
          status?: Database["public"]["Enums"]["user_status"]
          summary?: string | null
          summary_updated_at?: string | null
          tags?: string[]
          timezone?: string | null
          updated_at?: string
          wpp?: string
        }
        Relationships: []
      }
      whatsapp_phone_status: {
        Row: {
          display_phone_number: string | null
          history: Json
          last_checked_at: string
          messaging_limit_tier: string | null
          phone_number_id: string
          quality_rating: string | null
        }
        Insert: {
          display_phone_number?: string | null
          history?: Json
          last_checked_at?: string
          messaging_limit_tier?: string | null
          phone_number_id: string
          quality_rating?: string | null
        }
        Update: {
          display_phone_number?: string | null
          history?: Json
          last_checked_at?: string
          messaging_limit_tier?: string | null
          phone_number_id?: string
          quality_rating?: string | null
        }
        Relationships: []
      }
      workout_logs: {
        Row: {
          created_at: string
          duration_min: number | null
          estimated_kcal: number | null
          id: string
          intensity: string | null
          notes: string | null
          performed_at: string
          raw_message_id: string | null
          raw_provider_message_id: string | null
          snapshot_id: string | null
          user_id: string
          workout_type: string | null
        }
        Insert: {
          created_at?: string
          duration_min?: number | null
          estimated_kcal?: number | null
          id?: string
          intensity?: string | null
          notes?: string | null
          performed_at?: string
          raw_message_id?: string | null
          raw_provider_message_id?: string | null
          snapshot_id?: string | null
          user_id: string
          workout_type?: string | null
        }
        Update: {
          created_at?: string
          duration_min?: number | null
          estimated_kcal?: number | null
          id?: string
          intensity?: string | null
          notes?: string | null
          performed_at?: string
          raw_message_id?: string | null
          raw_provider_message_id?: string | null
          snapshot_id?: string | null
          user_id?: string
          workout_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "workout_logs_snapshot_id_fkey"
            columns: ["snapshot_id"]
            isOneToOne: false
            referencedRelation: "daily_snapshots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workout_logs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      workout_types: {
        Row: {
          category: string
          created_at: string
          description: string | null
          display_name: string
          id: string
          is_active: boolean
          kcal_per_min: number
          slug: string
          updated_at: string
        }
        Insert: {
          category: string
          created_at?: string
          description?: string | null
          display_name: string
          id?: string
          is_active?: boolean
          kcal_per_min: number
          slug: string
          updated_at?: string
        }
        Update: {
          category?: string
          created_at?: string
          description?: string | null
          display_name?: string
          id?: string
          is_active?: boolean
          kcal_per_min?: number
          slug?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      mv_kpis_daily: {
        Row: {
          cost_usd: number | null
          dau: number | null
          day: string | null
          messages_in: number | null
          messages_out: number | null
          new_users: number | null
          p50_latency_ms: number | null
          p95_latency_ms: number | null
          tool_success_rate: number | null
          tools_called: number | null
          tools_err: number | null
          tools_ok: number | null
        }
        Relationships: []
      }
      v_active_prompts: {
        Row: {
          allowed_tools: string[] | null
          buffer_debounce_ms: number | null
          config_id: string | null
          frequency_penalty: number | null
          helicone_cache: boolean | null
          llm_timeout_ms: number | null
          max_tokens: number | null
          max_tool_iterations: number | null
          model: string | null
          presence_penalty: number | null
          prompt_image: string | null
          stage: Database["public"]["Enums"]["agent_stage"] | null
          streaming: boolean | null
          stt_timeout_ms: number | null
          system_prompt: string | null
          temperature: number | null
          top_p: number | null
          vision_timeout_ms: number | null
          wait_seconds: number | null
        }
        Insert: {
          allowed_tools?: string[] | null
          buffer_debounce_ms?: number | null
          config_id?: string | null
          frequency_penalty?: number | null
          helicone_cache?: boolean | null
          llm_timeout_ms?: number | null
          max_tokens?: number | null
          max_tool_iterations?: number | null
          model?: string | null
          presence_penalty?: number | null
          prompt_image?: string | null
          stage?: Database["public"]["Enums"]["agent_stage"] | null
          streaming?: boolean | null
          stt_timeout_ms?: number | null
          system_prompt?: never
          temperature?: number | null
          top_p?: number | null
          vision_timeout_ms?: number | null
          wait_seconds?: number | null
        }
        Update: {
          allowed_tools?: string[] | null
          buffer_debounce_ms?: number | null
          config_id?: string | null
          frequency_penalty?: number | null
          helicone_cache?: boolean | null
          llm_timeout_ms?: number | null
          max_tokens?: number | null
          max_tool_iterations?: number | null
          model?: string | null
          presence_penalty?: number | null
          prompt_image?: string | null
          stage?: Database["public"]["Enums"]["agent_stage"] | null
          streaming?: boolean | null
          stt_timeout_ms?: number | null
          system_prompt?: never
          temperature?: number | null
          top_p?: number | null
          vision_timeout_ms?: number | null
          wait_seconds?: number | null
        }
        Relationships: []
      }
      v_attention_items: {
        Row: {
          created_at: string | null
          kind: string | null
          message: string | null
          name: string | null
          priority: number | null
          user_id: string | null
        }
        Relationships: []
      }
      v_cron_jobs: {
        Row: {
          active: boolean | null
          command: string | null
          database: string | null
          jobid: number | null
          jobname: string | null
          last_run: Json | null
          schedule: string | null
          username: string | null
        }
        Insert: {
          active?: boolean | null
          command?: string | null
          database?: string | null
          jobid?: number | null
          jobname?: string | null
          last_run?: never
          schedule?: string | null
          username?: string | null
        }
        Update: {
          active?: boolean | null
          command?: string | null
          database?: string | null
          jobid?: number | null
          jobname?: string | null
          last_run?: never
          schedule?: string | null
          username?: string | null
        }
        Relationships: []
      }
      v_daily_cost: {
        Row: {
          agent_stage: string | null
          avg_latency_ms: number | null
          calls: number | null
          day: string | null
          model_used: string | null
          total_cost_usd: number | null
          total_in_tokens: number | null
          total_out_tokens: number | null
        }
        Relationships: []
      }
      v_funnel_activation: {
        Row: {
          cohort_size: number | null
          cohort_week: string | null
          s1_messaged: number | null
          s2_onboarded: number | null
          s3_logged_meal: number | null
          s4_closed_block: number | null
          s5_paying: number | null
        }
        Relationships: []
      }
      v_mrr_summary: {
        Row: {
          active_subs: number | null
          churn_rate_30d: number | null
          churned_30d: number | null
          mrr_brl: number | null
          new_30d: number | null
        }
        Relationships: []
      }
      v_user_metrics: {
        Row: {
          activity_factor: number | null
          age: number | null
          bmr: number | null
          imc: number | null
          lbm: number | null
          protein_factor: number | null
          user_id: string | null
        }
        Insert: {
          activity_factor?: never
          age?: never
          bmr?: never
          imc?: never
          lbm?: never
          protein_factor?: never
          user_id?: string | null
        }
        Update: {
          activity_factor?: never
          age?: never
          bmr?: never
          imc?: never
          lbm?: never
          protein_factor?: never
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_profiles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      admin_role: { Args: never; Returns: string }
      agent_kpis: { Args: { days?: number }; Returns: Json }
      attention_cleanup_expired: { Args: never; Returns: number }
      attention_dismiss: {
        Args: { p_kind: string; p_reason?: string; p_user_id: string }
        Returns: undefined
      }
      attention_int: {
        Args: { p_default: number; p_key: string }
        Returns: number
      }
      attention_restore: {
        Args: { p_kind: string; p_user_id: string }
        Returns: undefined
      }
      attention_snooze: {
        Args: { p_hours?: number; p_kind: string; p_user_id: string }
        Returns: undefined
      }
      buffer_append_msg: {
        Args: { p_debounce_ms?: number; p_msg_entry: Json; p_user_id: string }
        Returns: Json
      }
      calc_workout_kcal: {
        Args: {
          p_duration_min: number
          p_intensity?: string
          p_slug: string
          p_weight_kg?: number
        }
        Returns: number
      }
      cron_run_now: { Args: { p_jobname: string }; Returns: Json }
      cron_toggle_job: {
        Args: { p_active: boolean; p_jobname: string }
        Returns: undefined
      }
      cron_update_schedule: {
        Args: { p_jobname: string; p_schedule: string }
        Returns: undefined
      }
      daily_close_user: {
        Args: { p_date?: string; p_user_id: string }
        Returns: Json
      }
      detect_country_from_wpp: { Args: { p_wpp: string }; Returns: string }
      dispatch_inngest_event: {
        Args: { p_data?: Json; p_delay_ms?: number; p_event_name: string }
        Returns: number
      }
      engagement_eligible_users: {
        Args: { p_quiet_hours_min?: number; p_window_label?: string }
        Returns: {
          current_protocol: Database["public"]["Enums"]["protocol_enum"]
          hours_since_last_in: number
          name: string
          timezone: string
          user_id: string
          wpp: string
        }[]
      }
      f_unaccent: { Args: { "": string }; Returns: string }
      get_global_config: { Args: { p_key: string }; Returns: Json }
      is_admin: { Args: never; Returns: boolean }
      match_food_phrases: {
        Args: {
          match_count: number
          match_language?: string
          match_threshold: number
          query_embedding: string
        }
        Returns: {
          id: string
          last_used_at: string
          phrase: string
          similarity: number
          tags: Json
          usage_count: number
        }[]
      }
      match_method_chunks: {
        Args: {
          filter_protocol?: string
          match_count?: number
          query_embedding: string
        }
        Returns: {
          content: string
          distance: number
          page_title: string
          protocol: string
        }[]
      }
      pause_user: {
        Args: { p_days: number; p_user_id: string }
        Returns: undefined
      }
      pending_approvals_expire_old: { Args: never; Returns: number }
      refresh_mv_kpis_daily: { Args: never; Returns: undefined }
      resolve_system_prompt: {
        Args: { p_language?: string; p_stage: string }
        Returns: string
      }
      resume_user: { Args: { p_user_id: string }; Returns: undefined }
      search_food_trgm: {
        Args: {
          max_results?: number
          min_similarity?: number
          p_country?: string
          search_term: string
        }
        Returns: {
          carbs_g: number
          category: string
          country_code: string
          fat_g: number
          fiber_g: number
          id: number
          kcal_per_100g: number
          name_pt: string
          protein_g: number
          similarity: number
        }[]
      }
      search_messages: {
        Args: { p_limit?: number; p_query: string }
        Returns: {
          agent_stage: string
          content: string
          created_at: string
          direction: string
          id: string
          rank: number
          user_id: string
          user_name: string
          user_wpp: string
        }[]
      }
      set_global_config: {
        Args: { p_key: string; p_value: Json }
        Returns: undefined
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      snapshot_add_meal: {
        Args: {
          p_calories_target?: number
          p_carbs: number
          p_date: string
          p_fat: number
          p_kcal: number
          p_protein: number
          p_protein_target?: number
          p_user_id: string
        }
        Returns: {
          calories_consumed: number
          calories_target: number | null
          carbs_g: number
          closed_at: string | null
          created_at: string
          current_protocol: Database["public"]["Enums"]["protocol_enum"] | null
          daily_balance: number | null
          date: string
          day_closed: boolean
          day_status: string
          deficit_accumulated: number
          exercise_calories: number
          fat_g: number
          gap_reminder_sent_at: string | null
          id: string
          protein_g: number
          protein_target: number | null
          sleep_hours: number | null
          steps: number | null
          training_done: boolean
          updated_at: string
          user_id: string
          water_consumed_ml: number
          xp_earned: number
        }
        SetofOptions: {
          from: "*"
          to: "daily_snapshots"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      snapshot_add_workout: {
        Args: {
          p_calories_target?: number
          p_date: string
          p_exercise_kcal: number
          p_protein_target?: number
          p_user_id: string
        }
        Returns: {
          calories_consumed: number
          calories_target: number | null
          carbs_g: number
          closed_at: string | null
          created_at: string
          current_protocol: Database["public"]["Enums"]["protocol_enum"] | null
          daily_balance: number | null
          date: string
          day_closed: boolean
          day_status: string
          deficit_accumulated: number
          exercise_calories: number
          fat_g: number
          gap_reminder_sent_at: string | null
          id: string
          protein_g: number
          protein_target: number | null
          sleep_hours: number | null
          steps: number | null
          training_done: boolean
          updated_at: string
          user_id: string
          water_consumed_ml: number
          xp_earned: number
        }
        SetofOptions: {
          from: "*"
          to: "daily_snapshots"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      tag_user: {
        Args: { p_tag: string; p_user_id: string }
        Returns: string[]
      }
      unaccent: { Args: { "": string }; Returns: string }
      untag_user: {
        Args: { p_tag: string; p_user_id: string }
        Returns: string[]
      }
      user_metadata_label_add: {
        Args: { p_extra_patch?: Json; p_label: string; p_user_id: string }
        Returns: Json
      }
      user_metadata_merge: {
        Args: { p_patch: Json; p_user_id: string }
        Returns: Json
      }
    }
    Enums: {
      activity_enum: "sedentario" | "leve" | "moderado" | "alto" | "atleta"
      agent_stage:
        | "coleta_dados"
        | "recomposicao"
        | "ganho_massa"
        | "manutencao"
        | "analista_diario"
        | "engajamento"
      config_status: "draft" | "testing" | "active" | "archived"
      content_type_enum: "text" | "audio" | "image" | "template" | "interactive"
      direction_enum: "in" | "out"
      goal_type_enum: "BF" | "IMC" | "peso_kg"
      hunger_enum: "pouca" | "moderada" | "muita"
      meal_type_enum: "cafe" | "almoco" | "lanche" | "jantar" | "ceia" | "outro"
      msg_role_enum: "user" | "assistant" | "system" | "tool"
      pending_registration_status:
        | "pending"
        | "confirmed"
        | "edited"
        | "expired"
        | "cancelled"
      plan_enum: "trial" | "mensal" | "anual"
      protocol_enum: "recomposicao" | "ganho_massa" | "manutencao"
      review_flag_enum:
        | "hallucination"
        | "great_response"
        | "needs_review"
        | "wrong_tool"
        | "tone_off"
        | "too_long"
      rule_tipo:
        | "recomposicao"
        | "ganho_massa"
        | "manutencao"
        | "coleta_dados"
        | "regras_gerais"
        | "vision"
        | "engajamento"
        | "analista_diario"
      sex_enum: "masculino" | "feminino"
      sub_status: "trial" | "active" | "past_due" | "canceled" | "expired"
      user_status: "active" | "blocked" | "deleted"
      water_enum: "pouco" | "moderado" | "bastante"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      activity_enum: ["sedentario", "leve", "moderado", "alto", "atleta"],
      agent_stage: [
        "coleta_dados",
        "recomposicao",
        "ganho_massa",
        "manutencao",
        "analista_diario",
        "engajamento",
      ],
      config_status: ["draft", "testing", "active", "archived"],
      content_type_enum: ["text", "audio", "image", "template", "interactive"],
      direction_enum: ["in", "out"],
      goal_type_enum: ["BF", "IMC", "peso_kg"],
      hunger_enum: ["pouca", "moderada", "muita"],
      meal_type_enum: ["cafe", "almoco", "lanche", "jantar", "ceia", "outro"],
      msg_role_enum: ["user", "assistant", "system", "tool"],
      pending_registration_status: [
        "pending",
        "confirmed",
        "edited",
        "expired",
        "cancelled",
      ],
      plan_enum: ["trial", "mensal", "anual"],
      protocol_enum: ["recomposicao", "ganho_massa", "manutencao"],
      review_flag_enum: [
        "hallucination",
        "great_response",
        "needs_review",
        "wrong_tool",
        "tone_off",
        "too_long",
      ],
      rule_tipo: [
        "recomposicao",
        "ganho_massa",
        "manutencao",
        "coleta_dados",
        "regras_gerais",
        "vision",
        "engajamento",
        "analista_diario",
      ],
      sex_enum: ["masculino", "feminino"],
      sub_status: ["trial", "active", "past_due", "canceled", "expired"],
      user_status: ["active", "blocked", "deleted"],
      water_enum: ["pouco", "moderado", "bastante"],
    },
  },
} as const
