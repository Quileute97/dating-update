/*
  # Cho phép tương tác với tài khoản ảo

  1. Cập nhật bảng user_likes để hỗ trợ fake users
  2. Cập nhật bảng friends để hỗ trợ fake users  
  3. Cập nhật bảng conversations để hỗ trợ fake users
  4. Cập nhật bảng post_likes để hỗ trợ fake user posts
  5. Cập nhật bảng comments để hỗ trợ fake user posts
  6. Tạo view unified để merge real và fake users
*/

-- 1. Cập nhật user_likes để hỗ trợ fake users
-- Thêm cột để phân biệt loại user
ALTER TABLE public.user_likes ADD COLUMN IF NOT EXISTS liker_type TEXT DEFAULT 'real';
ALTER TABLE public.user_likes ADD COLUMN IF NOT EXISTS liked_type TEXT DEFAULT 'real';

-- 2. Cập nhật friends để hỗ trợ fake users
ALTER TABLE public.friends ADD COLUMN IF NOT EXISTS user_type TEXT DEFAULT 'real';
ALTER TABLE public.friends ADD COLUMN IF NOT EXISTS friend_type TEXT DEFAULT 'real';

-- Thay đổi kiểu dữ liệu để hỗ trợ cả UUID và TEXT
ALTER TABLE public.friends ALTER COLUMN user_id TYPE TEXT;
ALTER TABLE public.friends ALTER COLUMN friend_id TYPE TEXT;

-- 3. Tạo view unified_users để merge real và fake users
CREATE OR REPLACE VIEW public.unified_users AS
SELECT 
  id::text as id,
  name,
  avatar,
  age,
  gender,
  bio,
  lat,
  lng,
  location_name,
  interests,
  album,
  height,
  job,
  education,
  is_dating_active,
  last_active,
  'real' as user_type,
  tai_khoan_hoat_dong as is_active
FROM public.profiles
WHERE tai_khoan_hoat_dong = true

UNION ALL

SELECT 
  id::text as id,
  name,
  avatar,
  age,
  gender,
  bio,
  lat,
  lng,
  location_name,
  interests,
  album,
  height,
  job,
  education,
  is_dating_active,
  last_active,
  'fake' as user_type,
  is_active
FROM public.fake_users
WHERE is_active = true;

-- 4. Tạo function để like fake user
CREATE OR REPLACE FUNCTION public.like_fake_user(
  liker_id_param TEXT,
  liked_id_param TEXT,
  liker_type_param TEXT DEFAULT 'real',
  liked_type_param TEXT DEFAULT 'fake'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  is_mutual BOOLEAN := false;
BEGIN
  -- Insert like
  INSERT INTO public.user_likes (liker_id, liked_id, liker_type, liked_type)
  VALUES (liker_id_param, liked_id_param, liker_type_param, liked_type_param)
  ON CONFLICT DO NOTHING;
  
  -- Check for mutual like
  SELECT EXISTS(
    SELECT 1 FROM public.user_likes 
    WHERE liker_id = liked_id_param 
    AND liked_id = liker_id_param
  ) INTO is_mutual;
  
  RETURN is_mutual;
END;
$$;

-- 5. Tạo function để comment trên fake user posts
CREATE OR REPLACE FUNCTION public.comment_on_fake_post(
  post_id_param UUID,
  user_id_param TEXT,
  content_param TEXT
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  comment_id UUID;
BEGIN
  -- Check if post exists in fake_user_posts
  IF EXISTS(SELECT 1 FROM public.fake_user_posts WHERE id = post_id_param) THEN
    -- Create a special comment record for fake posts
    INSERT INTO public.comments (id, post_id, user_id, content)
    VALUES (gen_random_uuid(), post_id_param, user_id_param, content_param)
    RETURNING id INTO comment_id;
    
    RETURN comment_id;
  END IF;
  
  RETURN NULL;
END;
$$;

-- 6. Tạo function để like fake user posts
CREATE OR REPLACE FUNCTION public.like_fake_post(
  post_id_param UUID,
  user_id_param TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
  -- Check if post exists in fake_user_posts
  IF EXISTS(SELECT 1 FROM public.fake_user_posts WHERE id = post_id_param) THEN
    -- Insert like for fake post
    INSERT INTO public.post_likes (post_id, user_id)
    VALUES (post_id_param, user_id_param)
    ON CONFLICT (post_id, user_id) DO NOTHING;
    
    RETURN true;
  END IF;
  
  RETURN false;
END;
$$;

-- 7. Cập nhật function get_timeline_with_fake_posts để hỗ trợ tương tác
CREATE OR REPLACE FUNCTION public.get_timeline_with_fake_posts(
    user_id_param TEXT DEFAULT NULL,
    limit_param INTEGER DEFAULT 20,
    offset_param INTEGER DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    content TEXT,
    media_url TEXT,
    media_type TEXT,
    location JSONB,
    sticker JSONB,
    created_at TIMESTAMP WITH TIME ZONE,
    user_id TEXT,
    user_name TEXT,
    user_avatar TEXT,
    user_age INTEGER,
    user_gender TEXT,
    is_fake_user BOOLEAN,
    like_count BIGINT,
    comment_count BIGINT,
    user_has_liked BOOLEAN
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    -- Real user posts
    SELECT 
        p.id,
        p.content,
        p.media_url,
        p.media_type,
        p.location,
        p.sticker,
        p.created_at,
        p.user_id,
        pr.name as user_name,
        pr.avatar as user_avatar,
        pr.age as user_age,
        pr.gender as user_gender,
        false as is_fake_user,
        COALESCE(like_counts.like_count, 0) as like_count,
        COALESCE(comment_counts.comment_count, 0) as comment_count,
        CASE WHEN user_likes.id IS NOT NULL THEN true ELSE false END as user_has_liked
    FROM public.posts p
    LEFT JOIN public.profiles pr ON p.user_id = pr.id
    LEFT JOIN (
        SELECT post_id, COUNT(*) as like_count
        FROM public.post_likes
        GROUP BY post_id
    ) like_counts ON p.id = like_counts.post_id
    LEFT JOIN (
        SELECT post_id, COUNT(*) as comment_count
        FROM public.comments
        GROUP BY post_id
    ) comment_counts ON p.id = comment_counts.post_id
    LEFT JOIN public.post_likes user_likes ON p.id = user_likes.post_id AND user_likes.user_id = user_id_param
    
    UNION ALL
    
    -- Fake user posts với tương tác thật
    SELECT 
        fup.id,
        fup.content,
        fup.media_url,
        fup.media_type,
        fup.location,
        fup.sticker,
        fup.created_at,
        fup.fake_user_id::text as user_id,
        fu.name as user_name,
        fu.avatar as user_avatar,
        fu.age as user_age,
        fu.gender as user_gender,
        true as is_fake_user,
        COALESCE(fake_like_counts.like_count, 0) as like_count,
        COALESCE(fake_comment_counts.comment_count, 0) as comment_count,
        CASE WHEN fake_user_likes.id IS NOT NULL THEN true ELSE false END as user_has_liked
    FROM public.fake_user_posts fup
    LEFT JOIN public.fake_users fu ON fup.fake_user_id = fu.id
    LEFT JOIN (
        SELECT post_id, COUNT(*) as like_count
        FROM public.post_likes
        GROUP BY post_id
    ) fake_like_counts ON fup.id = fake_like_counts.post_id
    LEFT JOIN (
        SELECT post_id, COUNT(*) as comment_count
        FROM public.comments
        GROUP BY post_id
    ) fake_comment_counts ON fup.id = fake_comment_counts.post_id
    LEFT JOIN public.post_likes fake_user_likes ON fup.id = fake_user_likes.post_id AND fake_user_likes.user_id = user_id_param
    WHERE fu.is_active = true
    
    ORDER BY created_at DESC
    LIMIT limit_param OFFSET offset_param;
END;
$$;

-- 8. Cập nhật RLS policies để cho phép tương tác với fake users

-- Cập nhật post_likes để cho phép like fake posts
DROP POLICY IF EXISTS "Users can create their own post likes" ON public.post_likes;
CREATE POLICY "Users can create post likes on any post"
  ON public.post_likes
  FOR INSERT
  WITH CHECK (auth.uid()::text = user_id);

-- Cập nhật comments để cho phép comment trên fake posts  
DROP POLICY IF EXISTS "Users can create their own comments" ON public.comments;
CREATE POLICY "Users can create comments on any post"
  ON public.comments
  FOR INSERT
  WITH CHECK (auth.uid()::text = user_id);

-- Cập nhật user_likes để cho phép like fake users
DROP POLICY IF EXISTS "Users can create their own user likes" ON public.user_likes;
CREATE POLICY "Users can create user likes for any user"
  ON public.user_likes
  FOR INSERT
  WITH CHECK (auth.uid()::text = liker_id);

-- 9. Tạo function để tạo conversation với fake user
CREATE OR REPLACE FUNCTION public.create_conversation_with_fake_user(
  real_user_id TEXT,
  fake_user_id TEXT
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  conversation_id UUID;
BEGIN
  -- Check if conversation already exists
  SELECT id INTO conversation_id
  FROM public.conversations
  WHERE user_real_id = real_user_id AND user_fake_id = fake_user_id
  LIMIT 1;
  
  -- If not exists, create new conversation
  IF conversation_id IS NULL THEN
    INSERT INTO public.conversations (user_real_id, user_fake_id)
    VALUES (real_user_id, fake_user_id)
    RETURNING id INTO conversation_id;
  END IF;
  
  RETURN conversation_id;
END;
$$;

-- 10. Tạo function để gửi friend request tới fake user
CREATE OR REPLACE FUNCTION public.send_friend_request_to_fake_user(
  real_user_id TEXT,
  fake_user_id TEXT
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  request_id UUID;
BEGIN
  -- Insert friend request
  INSERT INTO public.friends (user_id, friend_id, user_type, friend_type, status)
  VALUES (real_user_id, fake_user_id, 'real', 'fake', 'pending')
  RETURNING id INTO request_id;
  
  RETURN request_id;
END;
$$;