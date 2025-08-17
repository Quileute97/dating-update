import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { MessageCircle, Crown, ArrowRight } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useChatIntegration } from '@/hooks/useChatIntegration';

interface MatchedUser {
  id: string;
  name: string;
  avatar: string;
  distance?: number;
}

interface MatchedUsersViewProps {
  userId: string;
  onUpgradeClick: () => void;
}

const MatchedUsersView: React.FC<MatchedUsersViewProps> = ({ userId, onUpgradeClick }) => {
  const [matchedUsers, setMatchedUsers] = useState<MatchedUser[]>([]);
  const [loading, setLoading] = useState(true);
  const { startChatWith } = useChatIntegration();

  useEffect(() => {
    const fetchMatchedUsers = async () => {
      try {
        setLoading(true);
        
        // Get all profiles that have mutual likes (matches)
        const { data: matchedData, error: matchedError } = await supabase
          .from('user_likes')
          .select('liked_id, liker_id')
          .or(`liker_id.eq.${userId},liked_id.eq.${userId}`);
        
        if (matchedError) throw matchedError;
        
        // Find mutual matches
        const userLikes = matchedData?.filter(item => item.liker_id === userId).map(item => item.liked_id) || [];
        const otherLikes = matchedData?.filter(item => item.liked_id === userId).map(item => item.liker_id) || [];
        const mutualMatchIds = userLikes.filter(id => otherLikes.includes(id));
        
        // Get profile details for matched users
        if (mutualMatchIds.length > 0) {
          const { data: profilesData, error: profilesError } = await supabase
            .from('profiles')
            .select('id, name, avatar')
            .in('id', mutualMatchIds);
          
          if (profilesError) throw profilesError;