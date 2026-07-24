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
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
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
      coach_content_pack_entries: {
        Row: {
          created_at: string
          pack_id: string
          template_id: string
          template_version_id: string
        }
        Insert: {
          created_at?: string
          pack_id: string
          template_id: string
          template_version_id: string
        }
        Update: {
          created_at?: string
          pack_id?: string
          template_id?: string
          template_version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "coach_content_pack_entries_pack_id_fkey"
            columns: ["pack_id"]
            isOneToOne: false
            referencedRelation: "coach_content_packs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coach_content_pack_entries_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "coach_message_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coach_content_pack_entries_version_template_fkey"
            columns: ["template_version_id", "template_id"]
            isOneToOne: false
            referencedRelation: "coach_message_template_versions"
            referencedColumns: ["id", "template_id"]
          },
        ]
      }
      coach_content_packs: {
        Row: {
          activated_at: string | null
          activated_by: string | null
          approved_at: string | null
          approved_by: string | null
          archived_at: string | null
          created_at: string
          created_by: string | null
          effective_at: string | null
          id: string
          label: string
          parent_pack_id: string | null
          slug: string
          status: string
          updated_at: string
        }
        Insert: {
          activated_at?: string | null
          activated_by?: string | null
          approved_at?: string | null
          approved_by?: string | null
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          effective_at?: string | null
          id?: string
          label: string
          parent_pack_id?: string | null
          slug: string
          status?: string
          updated_at?: string
        }
        Update: {
          activated_at?: string | null
          activated_by?: string | null
          approved_at?: string | null
          approved_by?: string | null
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          effective_at?: string | null
          id?: string
          label?: string
          parent_pack_id?: string | null
          slug?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "coach_content_packs_parent_pack_id_fkey"
            columns: ["parent_pack_id"]
            isOneToOne: false
            referencedRelation: "coach_content_packs"
            referencedColumns: ["id"]
          },
        ]
      }
      coach_message_context_policies: {
        Row: {
          channel: string
          context: string
          cooldown_seconds: number
          created_at: string
          delivery_enabled: boolean
          max_per_local_day: number | null
          refresh_cadence: string
          updated_at: string
        }
        Insert: {
          channel: string
          context: string
          cooldown_seconds?: number
          created_at?: string
          delivery_enabled?: boolean
          max_per_local_day?: number | null
          refresh_cadence: string
          updated_at?: string
        }
        Update: {
          channel?: string
          context?: string
          cooldown_seconds?: number
          created_at?: string
          delivery_enabled?: boolean
          max_per_local_day?: number | null
          refresh_cadence?: string
          updated_at?: string
        }
        Relationships: []
      }
      coach_message_template_versions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          archived_at: string | null
          authored_by: string | null
          body: string
          content_hash: string
          created_at: string
          id: string
          provenance: string
          status: string
          subject: string | null
          template_id: string
          title: string | null
          updated_at: string
          version: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          archived_at?: string | null
          authored_by?: string | null
          body: string
          content_hash: string
          created_at?: string
          id?: string
          provenance: string
          status?: string
          subject?: string | null
          template_id: string
          title?: string | null
          updated_at?: string
          version: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          archived_at?: string | null
          authored_by?: string | null
          body?: string
          content_hash?: string
          created_at?: string
          id?: string
          provenance?: string
          status?: string
          subject?: string | null
          template_id?: string
          title?: string | null
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "coach_message_template_versions_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "coach_message_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      coach_message_templates: {
        Row: {
          allowed_variables: string[]
          channel: string
          context: string
          created_at: string
          id: string
          locale: string
          personality_code: string
          required_variables: string[]
          template_key: string
          variant: number
        }
        Insert: {
          allowed_variables?: string[]
          channel: string
          context: string
          created_at?: string
          id?: string
          locale: string
          personality_code: string
          required_variables?: string[]
          template_key: string
          variant: number
        }
        Update: {
          allowed_variables?: string[]
          channel?: string
          context?: string
          created_at?: string
          id?: string
          locale?: string
          personality_code?: string
          required_variables?: string[]
          template_key?: string
          variant?: number
        }
        Relationships: [
          {
            foreignKeyName: "coach_message_templates_personality_code_fkey"
            columns: ["personality_code"]
            isOneToOne: false
            referencedRelation: "coach_personalities"
            referencedColumns: ["code"]
          },
        ]
      }
      coach_message_usage: {
        Row: {
          channel: string
          context: string
          effective_personality: string
          event_key_hash: string | null
          id: string
          local_date: string
          locale: string
          occurred_at: string
          outcome: string
          pack_id: string | null
          reason: string
          requested_personality: string
          template_id: string | null
          template_version_id: string | null
          user_id: string
        }
        Insert: {
          channel: string
          context: string
          effective_personality: string
          event_key_hash?: string | null
          id?: string
          local_date: string
          locale: string
          occurred_at?: string
          outcome: string
          pack_id?: string | null
          reason: string
          requested_personality: string
          template_id?: string | null
          template_version_id?: string | null
          user_id: string
        }
        Update: {
          channel?: string
          context?: string
          effective_personality?: string
          event_key_hash?: string | null
          id?: string
          local_date?: string
          locale?: string
          occurred_at?: string
          outcome?: string
          pack_id?: string | null
          reason?: string
          requested_personality?: string
          template_id?: string | null
          template_version_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "coach_message_usage_pack_id_fkey"
            columns: ["pack_id"]
            isOneToOne: false
            referencedRelation: "coach_content_packs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coach_message_usage_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "coach_message_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coach_message_usage_template_version_id_fkey"
            columns: ["template_version_id"]
            isOneToOne: false
            referencedRelation: "coach_message_template_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coach_message_usage_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      coach_personalities: {
        Row: {
          active: boolean
          code: string
          created_at: string
          description_en_us: string
          description_pt_br: string
          name_en_us: string
          name_pt_br: string
          selectable: boolean
          updated_at: string
        }
        Insert: {
          active?: boolean
          code: string
          created_at?: string
          description_en_us: string
          description_pt_br: string
          name_en_us: string
          name_pt_br: string
          selectable?: boolean
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          description_en_us?: string
          description_pt_br?: string
          name_en_us?: string
          name_pt_br?: string
          selectable?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      content_assets: {
        Row: {
          actual_size_bytes: number | null
          bucket_id: string
          created_at: string
          created_by: string
          declared_size_bytes: number
          deleted_at: string | null
          etag: string | null
          id: string
          mime_type: string
          object_path: string
          status: string
          updated_at: string
          uploaded_at: string | null
        }
        Insert: {
          actual_size_bytes?: number | null
          bucket_id?: string
          created_at?: string
          created_by: string
          declared_size_bytes: number
          deleted_at?: string | null
          etag?: string | null
          id: string
          mime_type: string
          object_path: string
          status?: string
          updated_at?: string
          uploaded_at?: string | null
        }
        Update: {
          actual_size_bytes?: number | null
          bucket_id?: string
          created_at?: string
          created_by?: string
          declared_size_bytes?: number
          deleted_at?: string | null
          etag?: string | null
          id?: string
          mime_type?: string
          object_path?: string
          status?: string
          updated_at?: string
          uploaded_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "content_assets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
        ]
      }
      content_events: {
        Row: {
          content_version_id: string
          created_at: string
          event_key_hash: string
          event_type: string
          id: string
          occurred_at: string
          origin: string
          publication_id: string
          user_id: string
        }
        Insert: {
          content_version_id: string
          created_at?: string
          event_key_hash: string
          event_type: string
          id?: string
          occurred_at?: string
          origin: string
          publication_id: string
          user_id: string
        }
        Update: {
          content_version_id?: string
          created_at?: string
          event_key_hash?: string
          event_type?: string
          id?: string
          occurred_at?: string
          origin?: string
          publication_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "content_events_publication_id_fkey"
            columns: ["publication_id"]
            isOneToOne: false
            referencedRelation: "content_publications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_events_version_fkey"
            columns: ["content_version_id", "publication_id"]
            isOneToOne: false
            referencedRelation: "content_versions"
            referencedColumns: ["id", "publication_id"]
          },
        ]
      }
      content_publications: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          created_at: string
          created_by: string
          id: string
          slug: string
          updated_at: string
          version_counter: number
        }
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          created_at?: string
          created_by: string
          id?: string
          slug: string
          updated_at?: string
          version_counter?: number
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          created_at?: string
          created_by?: string
          id?: string
          slug?: string
          updated_at?: string
          version_counter?: number
        }
        Relationships: [
          {
            foreignKeyName: "content_publications_archived_by_fkey"
            columns: ["archived_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_publications_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
        ]
      }
      content_user_state: {
        Row: {
          completed_at: string | null
          completed_version_id: string | null
          created_at: string
          first_opened_at: string | null
          last_opened_at: string | null
          last_opened_version_id: string | null
          last_origin: string | null
          publication_id: string
          saved_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          completed_at?: string | null
          completed_version_id?: string | null
          created_at?: string
          first_opened_at?: string | null
          last_opened_at?: string | null
          last_opened_version_id?: string | null
          last_origin?: string | null
          publication_id: string
          saved_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          completed_at?: string | null
          completed_version_id?: string | null
          created_at?: string
          first_opened_at?: string | null
          last_opened_at?: string | null
          last_opened_version_id?: string | null
          last_origin?: string | null
          publication_id?: string
          saved_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "content_user_state_completed_version_fkey"
            columns: ["completed_version_id", "publication_id"]
            isOneToOne: false
            referencedRelation: "content_versions"
            referencedColumns: ["id", "publication_id"]
          },
          {
            foreignKeyName: "content_user_state_last_opened_version_fkey"
            columns: ["last_opened_version_id", "publication_id"]
            isOneToOne: false
            referencedRelation: "content_versions"
            referencedColumns: ["id", "publication_id"]
          },
          {
            foreignKeyName: "content_user_state_publication_id_fkey"
            columns: ["publication_id"]
            isOneToOne: false
            referencedRelation: "content_publications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_user_state_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      content_version_target_personalities: {
        Row: {
          content_version_id: string
          personality_code: string
        }
        Insert: {
          content_version_id: string
          personality_code: string
        }
        Update: {
          content_version_id?: string
          personality_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "content_version_target_personalities_content_version_id_fkey"
            columns: ["content_version_id"]
            isOneToOne: false
            referencedRelation: "content_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_version_target_personalities_personality_code_fkey"
            columns: ["personality_code"]
            isOneToOne: false
            referencedRelation: "coach_personalities"
            referencedColumns: ["code"]
          },
        ]
      }
      content_version_target_plans: {
        Row: {
          content_version_id: string
          plan: Database["public"]["Enums"]["plan_enum"]
        }
        Insert: {
          content_version_id: string
          plan: Database["public"]["Enums"]["plan_enum"]
        }
        Update: {
          content_version_id?: string
          plan?: Database["public"]["Enums"]["plan_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "content_version_target_plans_content_version_id_fkey"
            columns: ["content_version_id"]
            isOneToOne: false
            referencedRelation: "content_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      content_version_target_protocols: {
        Row: {
          content_version_id: string
          protocol: Database["public"]["Enums"]["protocol_enum"]
        }
        Insert: {
          content_version_id: string
          protocol: Database["public"]["Enums"]["protocol_enum"]
        }
        Update: {
          content_version_id?: string
          protocol?: Database["public"]["Enums"]["protocol_enum"]
        }
        Relationships: [
          {
            foreignKeyName: "content_version_target_protocols_content_version_id_fkey"
            columns: ["content_version_id"]
            isOneToOne: false
            referencedRelation: "content_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      content_versions: {
        Row: {
          authored_by: string
          body_hash: string | null
          body_markdown: string | null
          category: string | null
          cover_asset_id: string | null
          created_at: string
          excerpt: string | null
          featured_today: boolean
          id: string
          locale: string
          publication_id: string
          publish_at: string | null
          published_at: string | null
          published_by: string | null
          reading_time_minutes: number | null
          rejection_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          state: string
          submitted_at: string | null
          tags: string[]
          title: string | null
          updated_at: string
          version: number
        }
        Insert: {
          authored_by: string
          body_hash?: string | null
          body_markdown?: string | null
          category?: string | null
          cover_asset_id?: string | null
          created_at?: string
          excerpt?: string | null
          featured_today?: boolean
          id?: string
          locale: string
          publication_id: string
          publish_at?: string | null
          published_at?: string | null
          published_by?: string | null
          reading_time_minutes?: number | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          state?: string
          submitted_at?: string | null
          tags?: string[]
          title?: string | null
          updated_at?: string
          version: number
        }
        Update: {
          authored_by?: string
          body_hash?: string | null
          body_markdown?: string | null
          category?: string | null
          cover_asset_id?: string | null
          created_at?: string
          excerpt?: string | null
          featured_today?: boolean
          id?: string
          locale?: string
          publication_id?: string
          publish_at?: string | null
          published_at?: string | null
          published_by?: string | null
          reading_time_minutes?: number | null
          rejection_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          state?: string
          submitted_at?: string | null
          tags?: string[]
          title?: string | null
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "content_versions_authored_by_fkey"
            columns: ["authored_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_versions_cover_asset_id_fkey"
            columns: ["cover_asset_id"]
            isOneToOne: false
            referencedRelation: "content_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_versions_publication_id_fkey"
            columns: ["publication_id"]
            isOneToOne: false
            referencedRelation: "content_publications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_versions_published_by_fkey"
            columns: ["published_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_versions_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "admin_users"
            referencedColumns: ["id"]
          },
        ]
      }
      daily_gap_reminder_attempts: {
        Row: {
          attempt_id: string
          claim_key: string
          claimed_at: string
          date: string
          gap: Json
          last_error: string | null
          provider_message_id: string | null
          sent_at: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          attempt_id?: string
          claim_key: string
          claimed_at: string
          date: string
          gap: Json
          last_error?: string | null
          provider_message_id?: string | null
          sent_at?: string | null
          status: string
          updated_at?: string
          user_id: string
        }
        Update: {
          attempt_id?: string
          claim_key?: string
          claimed_at?: string
          date?: string
          gap?: Json
          last_error?: string | null
          provider_message_id?: string | null
          sent_at?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "daily_gap_reminder_attempts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
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
      engagement_delivery_attempts: {
        Row: {
          attempt_id: string
          claim_key: string
          claimed_at: string
          last_error: string | null
          local_date: string
          provider_message_ids: Json | null
          sent_at: string | null
          slot: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          attempt_id?: string
          claim_key: string
          claimed_at: string
          last_error?: string | null
          local_date: string
          provider_message_ids?: Json | null
          sent_at?: string | null
          slot: string
          status: string
          updated_at?: string
          user_id: string
        }
        Update: {
          attempt_id?: string
          claim_key?: string
          claimed_at?: string
          last_error?: string | null
          local_date?: string
          provider_message_ids?: Json | null
          sent_at?: string | null
          slot?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "engagement_delivery_attempts_user_id_fkey"
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
      entitlement_events: {
        Row: {
          created_at: string
          entitlement_id: string | null
          entitlement_key: string
          environment: string
          event_type: string
          id: string
          occurred_at: string
          processed_at: string | null
          processing_result: string
          provider_event_id: string
          source: string
          source_reference: string
          user_id: string
        }
        Insert: {
          created_at?: string
          entitlement_id?: string | null
          entitlement_key: string
          environment: string
          event_type: string
          id?: string
          occurred_at: string
          processed_at?: string | null
          processing_result?: string
          provider_event_id: string
          source: string
          source_reference: string
          user_id: string
        }
        Update: {
          created_at?: string
          entitlement_id?: string | null
          entitlement_key?: string
          environment?: string
          event_type?: string
          id?: string
          occurred_at?: string
          processed_at?: string | null
          processing_result?: string
          provider_event_id?: string
          source?: string
          source_reference?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "entitlement_events_entitlement_id_fkey"
            columns: ["entitlement_id"]
            isOneToOne: false
            referencedRelation: "user_entitlements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "entitlement_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
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
          is_verified: boolean
          kcal_per_100g: number | null
          name_norm: string | null
          name_pt: string
          protein_g: number | null
          source: string
          source_ref: string | null
        }
        Insert: {
          carbs_g?: number | null
          category?: string | null
          country_code?: string
          embedding?: string | null
          fat_g?: number | null
          fiber_g?: number | null
          id?: number
          is_verified?: boolean
          kcal_per_100g?: number | null
          name_norm?: string | null
          name_pt: string
          protein_g?: number | null
          source?: string
          source_ref?: string | null
        }
        Update: {
          carbs_g?: number | null
          category?: string | null
          country_code?: string
          embedding?: string | null
          fat_g?: number | null
          fiber_g?: number | null
          id?: number
          is_verified?: boolean
          kcal_per_100g?: number | null
          name_norm?: string | null
          name_pt?: string
          protein_g?: number | null
          source?: string
          source_ref?: string | null
        }
        Relationships: []
      }
      food_education_phrases: {
        Row: {
          active: boolean
          allowed_meal_types:
            | Database["public"]["Enums"]["meal_type_enum"][]
            | null
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
          allowed_meal_types?:
            | Database["public"]["Enums"]["meal_type_enum"][]
            | null
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
          allowed_meal_types?:
            | Database["public"]["Enums"]["meal_type_enum"][]
            | null
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
      hydration_logs: {
        Row: {
          amount_ml: number
          created_at: string
          id: string
          idempotency_key: string
          local_date: string
          occurred_at: string
          user_id: string
        }
        Insert: {
          amount_ml: number
          created_at?: string
          id?: string
          idempotency_key: string
          local_date: string
          occurred_at: string
          user_id: string
        }
        Update: {
          amount_ml?: number
          created_at?: string
          id?: string
          idempotency_key?: string
          local_date?: string
          occurred_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "hydration_logs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      legal_documents: {
        Row: {
          body: string
          body_hash: string | null
          created_at: string
          document_key: string
          id: string
          locale: string
          required_from: string
          version: string
        }
        Insert: {
          body: string
          body_hash?: string | null
          created_at?: string
          document_key: string
          id?: string
          locale: string
          required_from: string
          version: string
        }
        Update: {
          body?: string
          body_hash?: string | null
          created_at?: string
          document_key?: string
          id?: string
          locale?: string
          required_from?: string
          version?: string
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
          food_db_id: number | null
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
          food_db_id?: number | null
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
          food_db_id?: number | null
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
            foreignKeyName: "meal_logs_food_db_id_fkey"
            columns: ["food_db_id"]
            isOneToOne: false
            referencedRelation: "food_db"
            referencedColumns: ["id"]
          },
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
      media_assets: {
        Row: {
          actual_size_bytes: number | null
          bucket_id: string
          context_text: string | null
          created_at: string
          declared_size_bytes: number
          deleted_at: string | null
          etag: string | null
          failure_code: string | null
          failure_stage: string | null
          id: string
          kind: string
          mime_type: string
          object_path: string
          processed_at: string | null
          processing_request_id: string | null
          processing_result: Json | null
          retention_until: string | null
          source_request_hash: string
          status: string
          updated_at: string
          uploaded_at: string | null
          user_id: string
        }
        Insert: {
          actual_size_bytes?: number | null
          bucket_id: string
          context_text?: string | null
          created_at?: string
          declared_size_bytes: number
          deleted_at?: string | null
          etag?: string | null
          failure_code?: string | null
          failure_stage?: string | null
          id?: string
          kind: string
          mime_type: string
          object_path: string
          processed_at?: string | null
          processing_request_id?: string | null
          processing_result?: Json | null
          retention_until?: string | null
          source_request_hash: string
          status?: string
          updated_at?: string
          uploaded_at?: string | null
          user_id: string
        }
        Update: {
          actual_size_bytes?: number | null
          bucket_id?: string
          context_text?: string | null
          created_at?: string
          declared_size_bytes?: number
          deleted_at?: string | null
          etag?: string | null
          failure_code?: string | null
          failure_stage?: string | null
          id?: string
          kind?: string
          mime_type?: string
          object_path?: string
          processed_at?: string | null
          processing_request_id?: string | null
          processing_result?: Json | null
          retention_until?: string | null
          source_request_hash?: string
          status?: string
          updated_at?: string
          uploaded_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "media_assets_user_id_fkey"
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
          media_extension_count: number
          messages: Json
          user_id: string
        }
        Insert: {
          buffered_at?: string
          flush_after: string
          media_extension_count?: number
          messages?: Json
          user_id: string
        }
        Update: {
          buffered_at?: string
          flush_after?: string
          media_extension_count?: number
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
      message_dispatch_outbox: {
        Row: {
          created_at: string
          id: string
          messages: Json
          source_flush_after: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          messages: Json
          source_flush_after: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          messages?: Json
          source_flush_after?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_dispatch_outbox_user_id_fkey"
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
      mobile_api_idempotency: {
        Row: {
          attempt_count: number
          created_at: string
          expires_at: string
          id: string
          idempotency_key: string
          request_hash: string
          request_method: string
          request_route: string
          response_body: Json | null
          response_status: number | null
          state: string
          updated_at: string
          user_id: string
        }
        Insert: {
          attempt_count?: number
          created_at?: string
          expires_at?: string
          id?: string
          idempotency_key: string
          request_hash: string
          request_method: string
          request_route: string
          response_body?: Json | null
          response_status?: number | null
          state?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          attempt_count?: number
          created_at?: string
          expires_at?: string
          id?: string
          idempotency_key?: string
          request_hash?: string
          request_method?: string
          request_route?: string
          response_body?: Json | null
          response_status?: number | null
          state?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "mobile_api_idempotency_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      mobile_devices: {
        Row: {
          active: boolean
          apns_environment: string
          apns_token: string
          apns_token_hash: string | null
          created_at: string
          id: string
          installation_id: string
          last_seen_at: string
          platform: string
          updated_at: string
          user_id: string
        }
        Insert: {
          active?: boolean
          apns_environment: string
          apns_token: string
          apns_token_hash?: string | null
          created_at?: string
          id?: string
          installation_id: string
          last_seen_at?: string
          platform?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          active?: boolean
          apns_environment?: string
          apns_token?: string
          apns_token_hash?: string | null
          created_at?: string
          id?: string
          installation_id?: string
          last_seen_at?: string
          platform?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "mobile_devices_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_deliveries: {
        Row: {
          attempt_count: number
          channel: string
          coach_message_usage_id: string | null
          coach_template_version_id: string | null
          created_at: string
          error_code: string | null
          id: string
          locale: string | null
          mobile_device_id: string
          personality: string
          provider: string
          provider_message_id: string | null
          reminder_event_id: string
          routine_preview_mode: string | null
          scheduled_for: string
          status: string
          template_key: string
          updated_at: string
          user_id: string
        }
        Insert: {
          attempt_count?: number
          channel: string
          coach_message_usage_id?: string | null
          coach_template_version_id?: string | null
          created_at?: string
          error_code?: string | null
          id?: string
          locale?: string | null
          mobile_device_id: string
          personality: string
          provider: string
          provider_message_id?: string | null
          reminder_event_id: string
          routine_preview_mode?: string | null
          scheduled_for: string
          status?: string
          template_key: string
          updated_at?: string
          user_id: string
        }
        Update: {
          attempt_count?: number
          channel?: string
          coach_message_usage_id?: string | null
          coach_template_version_id?: string | null
          created_at?: string
          error_code?: string | null
          id?: string
          locale?: string | null
          mobile_device_id?: string
          personality?: string
          provider?: string
          provider_message_id?: string | null
          reminder_event_id?: string
          routine_preview_mode?: string | null
          scheduled_for?: string
          status?: string
          template_key?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_deliveries_coach_usage_owner_version_fkey"
            columns: [
              "coach_message_usage_id",
              "user_id",
              "coach_template_version_id",
            ]
            isOneToOne: false
            referencedRelation: "coach_message_usage"
            referencedColumns: ["id", "user_id", "template_version_id"]
          },
          {
            foreignKeyName: "notification_deliveries_coach_version_fkey"
            columns: ["coach_template_version_id"]
            isOneToOne: false
            referencedRelation: "coach_message_template_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_deliveries_device_owner_fkey"
            columns: ["mobile_device_id", "user_id"]
            isOneToOne: false
            referencedRelation: "mobile_devices"
            referencedColumns: ["id", "user_id"]
          },
          {
            foreignKeyName: "notification_deliveries_event_owner_fkey"
            columns: ["reminder_event_id", "user_id"]
            isOneToOne: false
            referencedRelation: "reminder_events"
            referencedColumns: ["id", "user_id"]
          },
          {
            foreignKeyName: "notification_deliveries_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          created_at: string
          daily_push_limit: number
          hydration_target_ml: number | null
          push_enabled: boolean
          quiet_hours_end: string | null
          quiet_hours_start: string | null
          routine_preview_mode: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          daily_push_limit?: number
          hydration_target_ml?: number | null
          push_enabled?: boolean
          quiet_hours_end?: string | null
          quiet_hours_start?: string | null
          routine_preview_mode?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          daily_push_limit?: number
          hydration_target_ml?: number | null
          push_enabled?: boolean
          quiet_hours_end?: string | null
          quiet_hours_start?: string | null
          routine_preview_mode?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
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
      reminder_events: {
        Row: {
          created_at: string
          id: string
          reminder_rule_id: string
          resolved_at: string | null
          routine_action_log_id: string | null
          routine_occurrence_key: string | null
          scheduled_for: string
          status: string
          suppression_reason: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          reminder_rule_id: string
          resolved_at?: string | null
          routine_action_log_id?: string | null
          routine_occurrence_key?: string | null
          scheduled_for: string
          status: string
          suppression_reason?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          reminder_rule_id?: string
          resolved_at?: string | null
          routine_action_log_id?: string | null
          routine_occurrence_key?: string | null
          scheduled_for?: string
          status?: string
          suppression_reason?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reminder_events_routine_action_owner_fkey"
            columns: [
              "routine_action_log_id",
              "user_id",
              "reminder_rule_id",
              "routine_occurrence_key",
            ]
            isOneToOne: false
            referencedRelation: "routine_adherence_logs"
            referencedColumns: [
              "id",
              "user_id",
              "reminder_rule_id",
              "occurrence_key",
            ]
          },
          {
            foreignKeyName: "reminder_events_rule_owner_fkey"
            columns: ["reminder_rule_id", "user_id"]
            isOneToOne: false
            referencedRelation: "reminder_rules"
            referencedColumns: ["id", "user_id"]
          },
          {
            foreignKeyName: "reminder_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      reminder_rules: {
        Row: {
          active: boolean
          category: string
          created_at: string
          deactivated_at: string | null
          id: string
          local_time: string
          meal_type: string | null
          routine_item_id: string | null
          template_key: string | null
          updated_at: string
          user_id: string
          weekdays: number[]
        }
        Insert: {
          active?: boolean
          category: string
          created_at?: string
          deactivated_at?: string | null
          id?: string
          local_time: string
          meal_type?: string | null
          routine_item_id?: string | null
          template_key?: string | null
          updated_at?: string
          user_id: string
          weekdays: number[]
        }
        Update: {
          active?: boolean
          category?: string
          created_at?: string
          deactivated_at?: string | null
          id?: string
          local_time?: string
          meal_type?: string | null
          routine_item_id?: string | null
          template_key?: string | null
          updated_at?: string
          user_id?: string
          weekdays?: number[]
        }
        Relationships: [
          {
            foreignKeyName: "reminder_rules_item_owner_type_fkey"
            columns: ["routine_item_id", "user_id", "category"]
            isOneToOne: false
            referencedRelation: "routine_items"
            referencedColumns: ["id", "user_id", "item_type"]
          },
          {
            foreignKeyName: "reminder_rules_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      routine_adherence_logs: {
        Row: {
          created_at: string
          id: string
          idempotency_key: string
          item_type: string
          occurred_at: string
          occurrence_key: string | null
          reminder_rule_id: string | null
          routine_item_id: string
          scheduled_for: string | null
          snoozed_until: string | null
          source: string | null
          status: string
          supersedes_log_id: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          idempotency_key: string
          item_type: string
          occurred_at: string
          occurrence_key?: string | null
          reminder_rule_id?: string | null
          routine_item_id: string
          scheduled_for?: string | null
          snoozed_until?: string | null
          source?: string | null
          status?: string
          supersedes_log_id?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          idempotency_key?: string
          item_type?: string
          occurred_at?: string
          occurrence_key?: string | null
          reminder_rule_id?: string | null
          routine_item_id?: string
          scheduled_for?: string | null
          snoozed_until?: string | null
          source?: string | null
          status?: string
          supersedes_log_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "routine_adherence_logs_item_owner_type_fkey"
            columns: ["routine_item_id", "user_id", "item_type"]
            isOneToOne: false
            referencedRelation: "routine_items"
            referencedColumns: ["id", "user_id", "item_type"]
          },
          {
            foreignKeyName: "routine_adherence_logs_rule_owner_type_fkey"
            columns: [
              "reminder_rule_id",
              "user_id",
              "routine_item_id",
              "item_type",
            ]
            isOneToOne: false
            referencedRelation: "reminder_rules"
            referencedColumns: ["id", "user_id", "routine_item_id", "category"]
          },
          {
            foreignKeyName: "routine_adherence_logs_supersedes_owner_fkey"
            columns: [
              "supersedes_log_id",
              "user_id",
              "routine_item_id",
              "item_type",
              "occurrence_key",
            ]
            isOneToOne: false
            referencedRelation: "routine_adherence_logs"
            referencedColumns: [
              "id",
              "user_id",
              "routine_item_id",
              "item_type",
              "occurrence_key",
            ]
          },
          {
            foreignKeyName: "routine_adherence_logs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      routine_items: {
        Row: {
          active: boolean
          archived_at: string | null
          created_at: string
          dose_text: string | null
          id: string
          item_type: string
          name: string
          origin: string | null
          reminders_enabled: boolean
          updated_at: string
          user_id: string
          version: number
        }
        Insert: {
          active?: boolean
          archived_at?: string | null
          created_at?: string
          dose_text?: string | null
          id?: string
          item_type: string
          name: string
          origin?: string | null
          reminders_enabled?: boolean
          updated_at?: string
          user_id: string
          version?: number
        }
        Update: {
          active?: boolean
          archived_at?: string | null
          created_at?: string
          dose_text?: string | null
          id?: string
          item_type?: string
          name?: string
          origin?: string | null
          reminders_enabled?: boolean
          updated_at?: string
          user_id?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "routine_items_user_id_fkey"
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
          attempt_count: number
          created_at: string
          currency: string
          event_type: string
          id: string
          last_error: string | null
          payload: Json | null
          processed_at: string | null
          processing_started_at: string | null
          processing_status: string
          provider_event_id: string | null
          subscription_id: string | null
          user_id: string | null
        }
        Insert: {
          amount_cents?: number | null
          attempt_count?: number
          created_at?: string
          currency?: string
          event_type: string
          id?: string
          last_error?: string | null
          payload?: Json | null
          processed_at?: string | null
          processing_started_at?: string | null
          processing_status?: string
          provider_event_id?: string | null
          subscription_id?: string | null
          user_id?: string | null
        }
        Update: {
          amount_cents?: number | null
          attempt_count?: number
          created_at?: string
          currency?: string
          event_type?: string
          id?: string
          last_error?: string | null
          payload?: Json | null
          processed_at?: string | null
          processing_started_at?: string | null
          processing_status?: string
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
          source_request_key: string | null
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
          source_request_key?: string | null
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
          source_request_key?: string | null
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
      user_coach_preferences: {
        Row: {
          created_at: string
          personality_code: string
          selected_at: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          personality_code: string
          selected_at?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          personality_code?: string
          selected_at?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_coach_preferences_personality_code_fkey"
            columns: ["personality_code"]
            isOneToOne: false
            referencedRelation: "coach_personalities"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "user_coach_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_entitlements: {
        Row: {
          access_expires_at: string | null
          actor_id: string | null
          cancel_at_period_end: boolean
          created_at: string
          entitlement_key: string
          environment: string
          grace_expires_at: string | null
          id: string
          last_provider_event_at: string
          last_provider_event_id: string
          plan: Database["public"]["Enums"]["plan_enum"] | null
          reason_code: string | null
          source: string
          source_reference: string
          starts_at: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          access_expires_at?: string | null
          actor_id?: string | null
          cancel_at_period_end?: boolean
          created_at?: string
          entitlement_key?: string
          environment: string
          grace_expires_at?: string | null
          id?: string
          last_provider_event_at: string
          last_provider_event_id: string
          plan?: Database["public"]["Enums"]["plan_enum"] | null
          reason_code?: string | null
          source: string
          source_reference: string
          starts_at?: string | null
          status: string
          updated_at?: string
          user_id: string
        }
        Update: {
          access_expires_at?: string | null
          actor_id?: string | null
          cancel_at_period_end?: boolean
          created_at?: string
          entitlement_key?: string
          environment?: string
          grace_expires_at?: string | null
          id?: string
          last_provider_event_at?: string
          last_provider_event_id?: string
          plan?: Database["public"]["Enums"]["plan_enum"] | null
          reason_code?: string | null
          source?: string
          source_reference?: string
          starts_at?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_entitlements_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
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
      user_legal_acceptances: {
        Row: {
          accepted_at: string
          body_hash: string
          created_at: string
          document_key: string
          id: string
          legal_document_id: string
          locale: string
          user_id: string
          version: string
        }
        Insert: {
          accepted_at?: string
          body_hash: string
          created_at?: string
          document_key: string
          id?: string
          legal_document_id: string
          locale: string
          user_id: string
          version: string
        }
        Update: {
          accepted_at?: string
          body_hash?: string
          created_at?: string
          document_key?: string
          id?: string
          legal_document_id?: string
          locale?: string
          user_id?: string
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_legal_acceptances_document_fkey"
            columns: [
              "legal_document_id",
              "document_key",
              "version",
              "locale",
              "body_hash",
            ]
            isOneToOne: false
            referencedRelation: "legal_documents"
            referencedColumns: [
              "id",
              "document_key",
              "version",
              "locale",
              "body_hash",
            ]
          },
          {
            foreignKeyName: "user_legal_acceptances_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_mascot_state: {
        Row: {
          changed_at: string
          created_at: string
          state: string
          updated_at: string
          user_id: string
        }
        Insert: {
          changed_at?: string
          created_at?: string
          state?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          changed_at?: string
          created_at?: string
          state?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_mascot_state_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_mascot_state_events: {
        Row: {
          event_key_hash: string
          from_state: string | null
          id: string
          occurred_at: string
          reason: string
          to_state: string
          user_id: string
        }
        Insert: {
          event_key_hash: string
          from_state?: string | null
          id?: string
          occurred_at?: string
          reason: string
          to_state: string
          user_id: string
        }
        Update: {
          event_key_hash?: string
          from_state?: string | null
          id?: string
          occurred_at?: string
          reason?: string
          to_state?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_mascot_state_events_user_id_fkey"
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
          auth_user_id: string | null
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
          wpp: string | null
        }
        Insert: {
          admin_notes?: string | null
          auth_user_id?: string | null
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
          wpp?: string | null
        }
        Update: {
          admin_notes?: string | null
          auth_user_id?: string | null
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
          wpp?: string | null
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
      vw_meal_state: {
        Row: {
          consumed_at: string | null
          kcal_orphaned: number | null
          last_transition_at: string | null
          meal_log_created_at: string | null
          meal_log_id: string | null
          meal_log_pmid: string | null
          meal_type: Database["public"]["Enums"]["meal_type_enum"] | null
          pending_created_at: string | null
          pending_id: string | null
          source_pmid: string | null
          state: string | null
          user_id: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      accept_mobile_legal_document: {
        Args: {
          p_body_hash: string
          p_document_key: string
          p_idempotency_key: string
          p_user_id: string
          p_version: string
        }
        Returns: Json
      }
      activate_coach_content_pack: {
        Args: { p_activated_by: string; p_now: string; p_pack_id: string }
        Returns: Json
      }
      activate_due_coach_content_pack: {
        Args: { p_now: string }
        Returns: Json
      }
      admin_role: { Args: never; Returns: string }
      advance_reevaluation_schedule: {
        Args: { p_closing_date: string; p_user_id: string }
        Returns: Json
      }
      agent_kpis: { Args: { days?: number }; Returns: Json }
      apply_entitlement_event: {
        Args: {
          p_access_expires_at: string
          p_actor_id?: string
          p_cancel_at_period_end: boolean
          p_entitlement_key: string
          p_environment: string
          p_event_type: string
          p_grace_expires_at: string
          p_occurred_at: string
          p_plan: Database["public"]["Enums"]["plan_enum"]
          p_provider_event_id: string
          p_reason_code?: string
          p_source: string
          p_source_reference: string
          p_starts_at: string
          p_status: string
          p_user_id: string
        }
        Returns: Json
      }
      approve_and_activate_coach_content_pack: {
        Args: {
          p_actor_id: string
          p_expected_snapshot_hash: string
          p_now: string
          p_pack_id: string
        }
        Returns: Json
      }
      archive_coach_content_pack: {
        Args: { p_actor_id: string; p_now: string; p_pack_id: string }
        Returns: Json
      }
      archive_content_publication: {
        Args: { p_actor_id: string; p_publication_id: string }
        Returns: Json
      }
      archive_mobile_routine_item: {
        Args: {
          p_idempotency_key: string
          p_item_id: string
          p_request_hash: string
          p_user_id: string
        }
        Returns: Json
      }
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
      bootstrap_patient_profile: { Args: never; Returns: string }
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
      claim_coach_message: {
        Args: {
          p_available_variables: string[]
          p_channel: string
          p_context: string
          p_event_key: string
          p_locale: string
          p_now?: string
          p_user_id: string
        }
        Returns: Json
      }
      claim_daily_gap_reminder: {
        Args: {
          p_claim_key: string
          p_date: string
          p_gap: Json
          p_now?: string
          p_user_id: string
        }
        Returns: Json
      }
      claim_due_message_dispatch: {
        Args: { p_now?: string; p_user_id: string }
        Returns: Json
      }
      claim_engagement_delivery: {
        Args: {
          p_claim_key: string
          p_local_date: string
          p_now?: string
          p_slot: string
          p_user_id: string
        }
        Returns: Json
      }
      claim_food_education_phrase: {
        Args: { cooldown_days?: number; phrase_ids: string[]; user_id: string }
        Returns: {
          cooldown_count: number
          exhausted: boolean
          last_used_at: string
          phrase_id: string
          selected_after_cooldown: boolean
          usage_count: number
        }[]
      }
      claim_media_asset_processing: {
        Args: { p_asset_id: string; p_request_id: string; p_user_id: string }
        Returns: Json
      }
      claim_mobile_api_request: {
        Args: {
          p_idempotency_key: string
          p_request_hash: string
          p_request_method: string
          p_request_route: string
          p_user_id: string
        }
        Returns: Json
      }
      claim_reminder_event: {
        Args: {
          p_claimed_at?: string
          p_reminder_rule_id: string
          p_scheduled_for: string
        }
        Returns: Json
      }
      claim_routine_snooze_event: {
        Args: { p_adherence_log_id: string; p_claimed_at: string }
        Returns: Json
      }
      claim_subscription_event: {
        Args: {
          p_event_type: string
          p_now?: string
          p_payload: Json
          p_provider_event_id: string
        }
        Returns: Json
      }
      clone_active_coach_content_pack: {
        Args: {
          p_actor_id: string
          p_label: string
          p_now: string
          p_slug: string
        }
        Returns: Json
      }
      complete_content_asset: {
        Args: {
          p_actor_id: string
          p_actual_size_bytes: number
          p_asset_id: string
          p_etag: string
        }
        Returns: Json
      }
      complete_media_asset_processing: {
        Args: {
          p_asset_id: string
          p_request_id: string
          p_result: Json
          p_user_id: string
        }
        Returns: boolean
      }
      complete_message_dispatch: {
        Args: { p_dispatch_id: string }
        Returns: Json
      }
      complete_mobile_api_request: {
        Args: {
          p_claim_id: string
          p_response_body: Json
          p_response_status: number
          p_user_id: string
        }
        Returns: boolean
      }
      create_content_asset: {
        Args: {
          p_actor_id: string
          p_asset_id: string
          p_declared_size_bytes: number
          p_mime_type: string
          p_object_path: string
        }
        Returns: Json
      }
      create_content_draft: {
        Args: {
          p_actor_id: string
          p_locale: string
          p_publication_id: string
          p_source_version_id?: string
        }
        Returns: Json
      }
      create_content_publication: {
        Args: { p_actor_id: string; p_slug: string }
        Returns: Json
      }
      create_mobile_routine_item: {
        Args: {
          p_idempotency_key: string
          p_item_type: string
          p_payload: Json
          p_request_hash: string
          p_user_id: string
        }
        Returns: Json
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
      deactivate_mobile_device: {
        Args: { p_device_id: string; p_user_id: string }
        Returns: boolean
      }
      delete_content_asset: {
        Args: {
          p_actor_id: string
          p_asset_id: string
          p_expected_status: string
        }
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
      ensure_user_initialized: { Args: { p_wpp: string }; Returns: string }
      extend_message_buffer_once: {
        Args: { p_new_flush_after: string; p_user_id: string }
        Returns: boolean
      }
      f_unaccent: { Args: { "": string }; Returns: string }
      fail_daily_gap_reminder: {
        Args: {
          p_attempt_id: string
          p_claim_key: string
          p_error: string
          p_now?: string
        }
        Returns: boolean
      }
      fail_engagement_delivery: {
        Args: {
          p_attempt_id: string
          p_claim_key: string
          p_error: string
          p_now?: string
        }
        Returns: boolean
      }
      fail_media_asset_processing: {
        Args: {
          p_asset_id: string
          p_failure_code: string
          p_request_id: string
          p_user_id: string
        }
        Returns: boolean
      }
      fail_mobile_api_request: {
        Args: { p_claim_id: string; p_user_id: string }
        Returns: boolean
      }
      finalize_daily_close_atomic: {
        Args: {
          p_badges_earned: string[]
          p_blocks_completed: number
          p_closed_at?: string
          p_current_streak: number
          p_day_status: string
          p_deficit_block: number
          p_last_active_date: string
          p_level: number
          p_longest_streak: number
          p_snapshot_id: string
          p_user_id: string
          p_xp_total: number
        }
        Returns: Json
      }
      finalize_daily_gap_reminder: {
        Args: {
          p_attempt_id: string
          p_claim_key: string
          p_content: string
          p_local_hour: number
          p_pattern_days: number
          p_provider: string
          p_provider_message_id: string
          p_sent_at: string
        }
        Returns: Json
      }
      finalize_due_routine_occurrences: {
        Args: {
          p_after_rule_id?: string
          p_after_scheduled_for?: string
          p_after_user_id?: string
          p_limit: number
          p_now: string
        }
        Returns: Json
      }
      finalize_engagement_delivery: {
        Args: {
          p_attempt_id: string
          p_claim_key: string
          p_completion_tokens?: number
          p_cost_usd?: number
          p_deliveries: Json
          p_latency_ms?: number
          p_model?: string
          p_phrase_id?: string
          p_phrase_used?: boolean
          p_prompt_tokens?: number
          p_provider: string
          p_reevaluation_context?: Json
          p_reevaluation_due?: boolean
          p_sent_at: string
        }
        Returns: Json
      }
      finish_subscription_event: {
        Args: {
          p_context?: Json
          p_error?: string
          p_now?: string
          p_provider_event_id: string
          p_success: boolean
        }
        Returns: Json
      }
      get_global_config: { Args: { p_key: string }; Returns: Json }
      get_mobile_content: {
        Args: { p_now?: string; p_publication_id: string; p_user_id: string }
        Returns: Json
      }
      get_mobile_legal_document: {
        Args: { p_document_key: string; p_user_id: string }
        Returns: Json
      }
      ingest_whatsapp_inbound: {
        Args: {
          p_buffer: boolean
          p_content: string
          p_content_type: string
          p_debounce_ms: number
          p_media_url: string
          p_provider_message_id: string
          p_raw_payload: Json
          p_received_at: string
          p_server_received_at: string
          p_wpp: string
        }
        Returns: Json
      }
      is_admin: { Args: never; Returns: boolean }
      list_due_reminder_rules: {
        Args: {
          p_after_rule_id?: string
          p_after_scheduled_for?: string
          p_fired_at: string
          p_limit?: number
          p_lookback_minutes?: number
        }
        Returns: {
          reminder_rule_id: string
          scheduled_for: string
        }[]
      }
      list_due_routine_snoozes: {
        Args: {
          p_after_log_id?: string
          p_after_snoozed_until?: string
          p_fired_at: string
          p_limit: number
          p_lookback_minutes: number
        }
        Returns: {
          adherence_log_id: string
          snoozed_until: string
        }[]
      }
      list_mobile_content: {
        Args: {
          p_category?: string
          p_cursor_publication_id?: string
          p_cursor_publish_at?: string
          p_limit?: number
          p_now?: string
          p_surface?: string
          p_user_id: string
        }
        Returns: Json
      }
      list_mobile_routine_history: {
        Args: {
          p_before_log_id?: string
          p_before_occurred_at?: string
          p_item_id: string
          p_item_type: string
          p_limit: number
          p_user_id: string
        }
        Returns: Json
      }
      list_mobile_routine_items: {
        Args: {
          p_include_archived?: boolean
          p_item_type: string
          p_now?: string
          p_user_id: string
        }
        Returns: Json
      }
      match_food_phrases: {
        Args: {
          match_count: number
          match_language?: string
          match_threshold: number
          query_embedding: string
        }
        Returns: {
          allowed_meal_types: Database["public"]["Enums"]["meal_type_enum"][]
          id: string
          last_used_at: string
          phrase: string
          similarity: number
          tags: Json
          usage_count: number
        }[]
      }
      pause_user: {
        Args: { p_days: number; p_user_id: string }
        Returns: undefined
      }
      pending_approvals_expire_old: { Args: never; Returns: number }
      publish_content_version: {
        Args: {
          p_actor_id: string
          p_publish_at?: string
          p_version_id: string
        }
        Returns: Json
      }
      record_hydration_atomic: {
        Args: {
          p_amount_ml: number
          p_idempotency_key: string
          p_local_date: string
          p_occurred_at: string
          p_user_id: string
        }
        Returns: Json
      }
      record_mobile_content_event: {
        Args: {
          p_event_key: string
          p_event_type: string
          p_now?: string
          p_origin: string
          p_publication_id: string
          p_user_id: string
          p_version: number
        }
        Returns: Json
      }
      record_routine_adherence_atomic: {
        Args: {
          p_expected_item_type: string
          p_idempotency_key: string
          p_routine_item_id: string
          p_taken_at: string
          p_user_id: string
        }
        Returns: Json
      }
      record_routine_occurrence_action_atomic: {
        Args: {
          p_expected_item_type: string
          p_idempotency_key: string
          p_item_id: string
          p_occurred_at: string
          p_reminder_rule_id: string
          p_scheduled_for: string
          p_snoozed_until: string
          p_status: string
          p_user_id: string
        }
        Returns: Json
      }
      refresh_mv_kpis_daily: { Args: never; Returns: undefined }
      register_meal_atomic: {
        Args: {
          p_calories_target?: number
          p_consumed_at?: string
          p_date: string
          p_items: Json
          p_meal_type: Database["public"]["Enums"]["meal_type_enum"]
          p_protein_target?: number
          p_provider_message_id?: string
          p_replace?: boolean
          p_replace_meal_types?: Database["public"]["Enums"]["meal_type_enum"][]
          p_user_id: string
        }
        Returns: Json
      }
      register_meal_atomic_scoped: {
        Args: {
          p_calories_target?: number
          p_consumed_at?: string
          p_date: string
          p_items: Json
          p_meal_type: Database["public"]["Enums"]["meal_type_enum"]
          p_protein_target?: number
          p_provider_message_id?: string
          p_replace?: boolean
          p_replace_log_ids?: string[]
          p_replace_meal_types?: Database["public"]["Enums"]["meal_type_enum"][]
          p_user_id: string
        }
        Returns: Json
      }
      register_workout_atomic: {
        Args: {
          p_calories_target?: number
          p_date: string
          p_duration_min: number
          p_estimated_kcal: number
          p_intensity?: string
          p_notes?: string
          p_performed_at?: string
          p_protein_target?: number
          p_provider_message_id?: string
          p_replace_recent?: boolean
          p_replace_since?: string
          p_user_id: string
          p_workout_type: string
        }
        Returns: Json
      }
      replace_pending_registration_atomic: {
        Args: {
          p_expires_at: string
          p_proposal: Json
          p_request_key?: string
          p_user_id: string
        }
        Returns: Json
      }
      reset_user_conversation_atomic: {
        Args: { p_user_id: string }
        Returns: Json
      }
      resolve_system_prompt: {
        Args: { p_language?: string; p_stage: string }
        Returns: string
      }
      resolve_user_entitlement: {
        Args: { p_entitlement_key?: string; p_now?: string; p_user_id: string }
        Returns: Json
      }
      resume_user: { Args: { p_user_id: string }; Returns: undefined }
      review_content_version: {
        Args: {
          p_actor_id: string
          p_decision: string
          p_rejection_reason?: string
          p_version_id: string
        }
        Returns: Json
      }
      revise_coach_assisted_draft_entries: {
        Args: {
          p_actor_id: string
          p_completion_tokens: number
          p_cost_usd: number
          p_group_key: string
          p_latency_ms: number
          p_model: string
          p_now: string
          p_pack_id: string
          p_prompt_tokens: number
          p_revisions: Json
        }
        Returns: Json
      }
      revise_coach_draft_entries: {
        Args: {
          p_actor_id: string
          p_now: string
          p_pack_id: string
          p_provenance: string
          p_revisions: Json
        }
        Returns: Json
      }
      rollback_coach_content_pack: {
        Args: { p_actor_id: string; p_now: string; p_pack_id: string }
        Returns: Json
      }
      save_content_draft: {
        Args: {
          p_actor_id: string
          p_draft: Json
          p_expected_updated_at: string
          p_version_id: string
        }
        Returns: Json
      }
      save_training_plan_atomic: {
        Args: {
          p_days_per_week: number
          p_equipment_summary: string
          p_generated_at: string
          p_generated_by: string
          p_notes: string
          p_plan_type: string
          p_request_key: string
          p_user_id: string
          p_valid_until: string
          p_version: number
          p_weekly_schedule: Json
        }
        Returns: Json
      }
      schedule_coach_content_pack: {
        Args: {
          p_actor_id: string
          p_effective_at: string
          p_expected_snapshot_hash: string
          p_now: string
          p_pack_id: string
        }
        Returns: Json
      }
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
      set_mobile_content_saved: {
        Args: {
          p_event_key: string
          p_now?: string
          p_origin: string
          p_publication_id: string
          p_saved: boolean
          p_user_id: string
          p_version: number
        }
        Returns: Json
      }
      set_user_coach_personality: {
        Args: { p_personality: string; p_user_id: string }
        Returns: Json
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
      submit_content_version: {
        Args: {
          p_actor_id: string
          p_expected_updated_at: string
          p_version_id: string
        }
        Returns: Json
      }
      sync_stripe_subscription_entitlement: {
        Args: {
          p_environment?: string
          p_occurred_at: string
          p_provider_event_id: string
          p_subscription_id: string
        }
        Returns: Json
      }
      tag_user: {
        Args: { p_tag: string; p_user_id: string }
        Returns: string[]
      }
      transition_user_mascot_state: {
        Args: {
          p_event_key: string
          p_next_state: string
          p_reason: string
          p_user_id: string
        }
        Returns: Json
      }
      unaccent: { Args: { "": string }; Returns: string }
      untag_user: {
        Args: { p_tag: string; p_user_id: string }
        Returns: string[]
      }
      update_mobile_routine_item: {
        Args: {
          p_expected_version: number
          p_idempotency_key: string
          p_item_id: string
          p_patch: Json
          p_request_hash: string
          p_user_id: string
        }
        Returns: Json
      }
      update_notification_preferences_atomic: {
        Args: { p_patch: Json; p_user_id: string }
        Returns: Json
      }
      upsert_mobile_device: {
        Args: {
          p_apns_environment: string
          p_apns_token: string
          p_installation_id: string
          p_user_id: string
        }
        Returns: string
      }
      user_metadata_label_add: {
        Args: { p_extra_patch?: Json; p_label: string; p_user_id: string }
        Returns: Json
      }
      user_metadata_merge: {
        Args: { p_patch: Json; p_user_id: string }
        Returns: Json
      }
      validate_coach_content_pack: {
        Args: { p_pack_id: string }
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
  graphql_public: {
    Enums: {},
  },
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
      ],
      sex_enum: ["masculino", "feminino"],
      sub_status: ["trial", "active", "past_due", "canceled", "expired"],
      user_status: ["active", "blocked", "deleted"],
      water_enum: ["pouco", "moderado", "bastante"],
    },
  },
} as const
