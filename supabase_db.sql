-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.profiles (
  id uuid NOT NULL,
  email text NOT NULL,
  display_name text NOT NULL,
  role USER-DEFINED NOT NULL DEFAULT 'customer'::user_role,
  phone text,
  avatar_url text,
  bio text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);
CREATE TABLE public.events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  event_name text NOT NULL,
  description text,
  event_date timestamp with time zone,
  venue text,
  latitude numeric,
  longitude numeric,
  is_public boolean NOT NULL DEFAULT true,
  poster_url text,
  max_tickets integer CHECK (max_tickets > 0),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT events_pkey PRIMARY KEY (id),
  CONSTRAINT events_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.event_ticket_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL,
  ticket_type USER-DEFINED NOT NULL,
  price numeric NOT NULL CHECK (price >= 0::numeric),
  quantity_available integer NOT NULL CHECK (quantity_available >= 0),
  quantity_sold integer NOT NULL DEFAULT 0 CHECK (quantity_sold >= 0),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT event_ticket_types_pkey PRIMARY KEY (id),
  CONSTRAINT event_ticket_types_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id)
);
CREATE TABLE public.tickets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  ticket_id text NOT NULL,
  block_index integer NOT NULL CHECK (block_index >= 0),
  stego_url text,
  event_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  owner_name text NOT NULL,
  ticket_type USER-DEFINED NOT NULL,
  price numeric NOT NULL CHECK (price >= 0::numeric),
  is_sold boolean NOT NULL DEFAULT false,
  sold_to uuid,
  sold_at timestamp with time zone,
  buyer_email text,
  buyer_phone text,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  scanned_at timestamp with time zone,
  CONSTRAINT tickets_pkey PRIMARY KEY (id),
  CONSTRAINT tickets_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id),
  CONSTRAINT tickets_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id),
  CONSTRAINT tickets_sold_to_fkey FOREIGN KEY (sold_to) REFERENCES auth.users(id)
);
CREATE TABLE public.payments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL,
  event_id uuid NOT NULL,
  buyer_id uuid NOT NULL,
  amount numeric NOT NULL CHECK (amount >= 0::numeric),
  currency text NOT NULL DEFAULT 'MWK'::text,
  payment_method USER-DEFINED,
  card_last_four text CHECK (card_last_four ~ '^\d{4}$'::text),
  card_brand text,
  status USER-DEFINED NOT NULL DEFAULT 'pending'::payment_status,
  transaction_reference text UNIQUE,
  processed_at timestamp with time zone,
  failure_reason text,
  buyer_name text NOT NULL,
  buyer_email text NOT NULL,
  buyer_phone text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT payments_pkey PRIMARY KEY (id),
  CONSTRAINT payments_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id),
  CONSTRAINT payments_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id),
  CONSTRAINT payments_buyer_id_fkey FOREIGN KEY (buyer_id) REFERENCES auth.users(id)
);